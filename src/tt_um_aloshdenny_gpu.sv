`default_nettype none
`timescale 1ns/1ns

module tt_um_aloshdenny_gpu (
`ifdef USE_POWER_PINS
    inout  wire       VPWR,
    inout  wire       VGND,
`endif
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Output Enable (active high)
    input  wire       ena,      // always 1 to run the design
    input  wire       clk,      // clock
    input  wire       rst_n     // active low reset
);

    // =========================================================================
    // 1. Reset Synchronizer (§ 5.7)
    // =========================================================================
    reg rst_sync_0, rst_sync_1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rst_sync_0 <= 1'b0;
            rst_sync_1 <= 1'b0;
        end else begin
            rst_sync_0 <= 1'b1;
            rst_sync_1 <= rst_sync_0;
        end
    end
    wire gpu_reset = !rst_sync_1; // Active-high reset for internal logic

    // =========================================================================
    // 2. Control Signal Mapping
    // =========================================================================
    wire start = ui_in[7];
    wire [7:0] device_control_data = {1'b0, ui_in[6:0]}; // thread_count mapped to lower 7 bits
    wire device_control_write_enable = (ui_in[6:0] != 7'd0);

    // =========================================================================
    // 3. Parallel GPU Interface Signals
    // =========================================================================
    localparam DATA_MEM_ADDR_BITS = 19;
    localparam DATA_MEM_DATA_BITS = 16;
    localparam DATA_MEM_NUM_CHANNELS = 4;   // 2 cores × 2 threads
    localparam PROGRAM_MEM_ADDR_BITS = 9;
    localparam PROGRAM_MEM_DATA_BITS = 16;
    localparam PROGRAM_MEM_NUM_CHANNELS = 2;

    wire gpu_done;

    // Program Memory
    wire [PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_valid;
    wire [PROGRAM_MEM_ADDR_BITS*PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_address_flat;
    reg  [PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_ready;
    reg  [PROGRAM_MEM_DATA_BITS*PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_data_flat;

    // Data Memory
    wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_valid;
    wire [DATA_MEM_ADDR_BITS*DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_address_flat;
    reg  [DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_ready;
    reg  [DATA_MEM_DATA_BITS*DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_data_flat;
    wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_valid;
    wire [DATA_MEM_ADDR_BITS*DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_address_flat;
    wire [DATA_MEM_DATA_BITS*DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_data_flat;
    reg  [DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_ready;

    // On-die 128B RAM32 scratchpad (high-speed data cache / scratch)
    wire        scratch_ram_en;
    wire [3:0]  scratch_ram_we;
    wire [4:0]  scratch_ram_addr;
    wire [31:0] scratch_ram_di;
    wire [31:0] scratch_ram_do;

    // Instance name must stay `ram1` — matched by src/config.json MACROS
    RAM32 ram1 (
`ifdef USE_POWER_PINS
        .VPWR(VPWR),
        .VGND(VGND),
`endif
        .CLK (clk),
        .EN0 (scratch_ram_en),
        .WE0 (scratch_ram_we),
        .A0  (scratch_ram_addr),
        .Di0 (scratch_ram_di),
        .Do0 (scratch_ram_do)
    );

    // GPU Instantiation
    gpu #(
        .DATA_MEM_ADDR_BITS(DATA_MEM_ADDR_BITS),
        .DATA_MEM_DATA_BITS(DATA_MEM_DATA_BITS),
        .DATA_MEM_NUM_CHANNELS(DATA_MEM_NUM_CHANNELS),
        .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
        .PROGRAM_MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS),
        .PROGRAM_MEM_NUM_CHANNELS(PROGRAM_MEM_NUM_CHANNELS)
    ) gpu_core (
        .clk(clk),
        .reset(gpu_reset),
        .start(start),
        .done(gpu_done),
        .device_control_write_enable(device_control_write_enable),
        .device_control_data(device_control_data),

        .program_mem_read_valid(program_mem_read_valid),
        .program_mem_read_address_flat(program_mem_read_address_flat),
        .program_mem_read_ready(program_mem_read_ready),
        .program_mem_read_data_flat(program_mem_read_data_flat),

        .data_mem_read_valid(data_mem_read_valid),
        .data_mem_read_address_flat(data_mem_read_address_flat),
        .data_mem_read_ready(data_mem_read_ready),
        .data_mem_read_data_flat(data_mem_read_data_flat),
        .data_mem_write_valid(data_mem_write_valid),
        .data_mem_write_address_flat(data_mem_write_address_flat),
        .data_mem_write_data_flat(data_mem_write_data_flat),
        .data_mem_write_ready(data_mem_write_ready),

        .scratch_ram_en(scratch_ram_en),
        .scratch_ram_we(scratch_ram_we),
        .scratch_ram_addr(scratch_ram_addr),
        .scratch_ram_di(scratch_ram_di),
        .scratch_ram_do(scratch_ram_do)
    );

    // =========================================================================
    // 4. Time-Multiplexed External Memory Interface Controller
    // =========================================================================
    reg [3:0] state;
    localparam STATE_IDLE      = 4'd0;
    localparam STATE_ADDR0     = 4'd1;
    localparam STATE_ADDR1     = 4'd2;
    localparam STATE_ADDR2     = 4'd3;
    localparam STATE_DATA0     = 4'd4;
    localparam STATE_DATA1     = 4'd5;
    localparam STATE_ACK       = 4'd6;

    // Latched request metadata
    reg [DATA_MEM_ADDR_BITS-1:0] active_addr;
    reg [DATA_MEM_DATA_BITS-1:0] active_write_data;
    reg                          active_is_write;
    reg                          active_mem_sel; // 0 = Program, 1 = Data
    reg [3:0]                    active_channel_id; // 0-1: Program, 2-5: Data

    // SRAM / bus controls
    reg [7:0] bus_out;
    reg [7:0] bus_oe;
    reg       mem_we;
    reg       mem_re;
    reg       ale;
    reg       mem_sel;

    reg [DATA_MEM_DATA_BITS-1:0] read_data_latch;

    // Bidirectional pin drive
    assign uio_out = bus_out;
    assign uio_oe  = bus_oe;

    // Grounding unused output pins (§ 5.3)
    assign uo_out[7:5] = 3'b000;
    assign uo_out[4]   = mem_sel;
    assign uo_out[3]   = ale;
    assign uo_out[2]   = mem_re;
    assign uo_out[1]   = mem_we;
    assign uo_out[0]   = gpu_done;

    // Memory request serialization arbiter
    always @(posedge clk) begin
        if (gpu_reset) begin
            state <= STATE_IDLE;
            active_addr <= 0;
            active_write_data <= 0;
            active_is_write <= 0;
            active_mem_sel <= 0;
            active_channel_id <= 0;
            bus_out <= 8'h00;
            bus_oe <= 8'h00;
            mem_we <= 1'b0;
            mem_re <= 1'b0;
            ale <= 1'b0;
            mem_sel <= 1'b0;
            read_data_latch <= 0;
            program_mem_read_ready <= 2'b00;
            program_mem_read_data_flat <= 0;
            data_mem_read_ready <= 4'h0;
            data_mem_read_data_flat <= 0;
            data_mem_write_ready <= 4'h0;
        end else begin
            // Pulse reset signals
            program_mem_read_ready <= 2'b00;
            data_mem_read_ready <= 4'h0;
            data_mem_write_ready <= 4'h0;

            case (state)
                STATE_IDLE: begin
                    bus_oe <= 8'h00;
                    mem_we <= 1'b0;
                    mem_re <= 1'b0;
                    ale <= 1'b0;

                    // Fixed priority encoder (2 program + 4 data channels)
                    if (program_mem_read_valid[0]) begin
                        active_addr <= { {(DATA_MEM_ADDR_BITS-PROGRAM_MEM_ADDR_BITS){1'b0}}, program_mem_read_address_flat[PROGRAM_MEM_ADDR_BITS-1:0] };
                        active_is_write <= 1'b0;
                        active_mem_sel <= 1'b0; // Program
                        active_channel_id <= 4'd0;
                        state <= STATE_ADDR0;
                    end else if (program_mem_read_valid[1]) begin
                        active_addr <= { {(DATA_MEM_ADDR_BITS-PROGRAM_MEM_ADDR_BITS){1'b0}}, program_mem_read_address_flat[2*PROGRAM_MEM_ADDR_BITS-1:PROGRAM_MEM_ADDR_BITS] };
                        active_is_write <= 1'b0;
                        active_mem_sel <= 1'b0; // Program
                        active_channel_id <= 4'd1;
                        state <= STATE_ADDR0;
                    end else if (data_mem_read_valid[0]) begin
                        active_addr <= data_mem_read_address_flat[DATA_MEM_ADDR_BITS-1:0];
                        active_is_write <= 1'b0;
                        active_mem_sel <= 1'b1; // Data
                        active_channel_id <= 4'd2;
                        state <= STATE_ADDR0;
                    end else if (data_mem_write_valid[0]) begin
                        active_addr <= data_mem_write_address_flat[DATA_MEM_ADDR_BITS-1:0];
                        active_write_data <= data_mem_write_data_flat[DATA_MEM_DATA_BITS-1:0];
                        active_is_write <= 1'b1;
                        active_mem_sel <= 1'b1; // Data
                        active_channel_id <= 4'd2;
                        state <= STATE_ADDR0;
                    end else if (data_mem_read_valid[1]) begin
                        active_addr <= data_mem_read_address_flat[2*DATA_MEM_ADDR_BITS-1:DATA_MEM_ADDR_BITS];
                        active_is_write <= 1'b0;
                        active_mem_sel <= 1'b1;
                        active_channel_id <= 4'd3;
                        state <= STATE_ADDR0;
                    end else if (data_mem_write_valid[1]) begin
                        active_addr <= data_mem_write_address_flat[2*DATA_MEM_ADDR_BITS-1:DATA_MEM_ADDR_BITS];
                        active_write_data <= data_mem_write_data_flat[2*DATA_MEM_DATA_BITS-1:DATA_MEM_DATA_BITS];
                        active_is_write <= 1'b1;
                        active_mem_sel <= 1'b1;
                        active_channel_id <= 4'd3;
                        state <= STATE_ADDR0;
                    end else if (data_mem_read_valid[2]) begin
                        active_addr <= data_mem_read_address_flat[3*DATA_MEM_ADDR_BITS-1:2*DATA_MEM_ADDR_BITS];
                        active_is_write <= 1'b0;
                        active_mem_sel <= 1'b1;
                        active_channel_id <= 4'd4;
                        state <= STATE_ADDR0;
                    end else if (data_mem_write_valid[2]) begin
                        active_addr <= data_mem_write_address_flat[3*DATA_MEM_ADDR_BITS-1:2*DATA_MEM_ADDR_BITS];
                        active_write_data <= data_mem_write_data_flat[3*DATA_MEM_DATA_BITS-1:2*DATA_MEM_DATA_BITS];
                        active_is_write <= 1'b1;
                        active_mem_sel <= 1'b1;
                        active_channel_id <= 4'd4;
                        state <= STATE_ADDR0;
                    end else if (data_mem_read_valid[3]) begin
                        active_addr <= data_mem_read_address_flat[4*DATA_MEM_ADDR_BITS-1:3*DATA_MEM_ADDR_BITS];
                        active_is_write <= 1'b0;
                        active_mem_sel <= 1'b1;
                        active_channel_id <= 4'd5;
                        state <= STATE_ADDR0;
                    end else if (data_mem_write_valid[3]) begin
                        active_addr <= data_mem_write_address_flat[4*DATA_MEM_ADDR_BITS-1:3*DATA_MEM_ADDR_BITS];
                        active_write_data <= data_mem_write_data_flat[4*DATA_MEM_DATA_BITS-1:3*DATA_MEM_DATA_BITS];
                        active_is_write <= 1'b1;
                        active_mem_sel <= 1'b1;
                        active_channel_id <= 4'd5;
                        state <= STATE_ADDR0;
                    end
                end

                // Address Cycle 0: drive lower 8 bits of address
                STATE_ADDR0: begin
                    bus_out <= active_addr[7:0];
                    bus_oe  <= 8'hFF;
                    ale <= 1'b1;
                    mem_sel <= active_mem_sel;
                    state <= STATE_ADDR1;
                end

                // Address Cycle 1: drive middle 8 bits of address
                STATE_ADDR1: begin
                    bus_out <= active_addr[15:8];
                    bus_oe  <= 8'hFF;
                    ale <= 1'b1;
                    state <= STATE_ADDR2;
                end

                // Address Cycle 2: drive upper 3 bits of address & mem control bits
                STATE_ADDR2: begin
                    bus_out <= {active_mem_sel, active_is_write, 3'b000, active_addr[18:16]};
                    bus_oe  <= 8'hFF;
                    ale <= 1'b1;
                    state <= STATE_DATA0;
                end

                // Data Cycle 0: transfer lower data byte
                STATE_DATA0: begin
                    ale <= 1'b0;
                    if (active_is_write) begin
                        bus_out <= active_write_data[7:0];
                        bus_oe  <= 8'hFF;
                        mem_we  <= 1'b1;
                    end else begin
                        bus_oe  <= 8'h00; // Switch to input mode
                        mem_re  <= 1'b1;
                    end
                    state <= STATE_DATA1;
                end

                // Data Cycle 1: transfer upper data byte & latch reads
                STATE_DATA1: begin
                    if (active_is_write) begin
                        bus_out <= active_write_data[15:8];
                        bus_oe  <= 8'hFF;
                        mem_we  <= 1'b1;
                    end else begin
                        read_data_latch[7:0] <= uio_in;
                        bus_oe  <= 8'h00;
                        mem_re  <= 1'b1;
                    end
                    state <= STATE_ACK;
                end

                // Acknowledge Cycle: update GPU inputs and return to idle
                STATE_ACK: begin
                    mem_we <= 1'b0;
                    mem_re <= 1'b0;
                    bus_oe <= 8'h00;

                    if (!active_is_write) begin
                        read_data_latch[15:8] <= uio_in;
                    end

                    // Send response flags back to specific GPU read/write channel
                    case (active_channel_id)
                        4'd0: begin
                            program_mem_read_ready[0] <= 1'b1;
                            program_mem_read_data_flat[PROGRAM_MEM_DATA_BITS-1:0] <= (!active_is_write) ? {uio_in, read_data_latch[7:0]} : 16'd0;
                        end
                        4'd1: begin
                            program_mem_read_ready[1] <= 1'b1;
                            program_mem_read_data_flat[2*PROGRAM_MEM_DATA_BITS-1:PROGRAM_MEM_DATA_BITS] <= (!active_is_write) ? {uio_in, read_data_latch[7:0]} : 16'd0;
                        end
                        4'd2: begin
                            if (active_is_write) begin
                                data_mem_write_ready[0] <= 1'b1;
                            end else begin
                                data_mem_read_ready[0] <= 1'b1;
                                data_mem_read_data_flat[DATA_MEM_DATA_BITS-1:0] <= {uio_in, read_data_latch[7:0]};
                            end
                        end
                        4'd3: begin
                            if (active_is_write) begin
                                data_mem_write_ready[1] <= 1'b1;
                            end else begin
                                data_mem_read_ready[1] <= 1'b1;
                                data_mem_read_data_flat[2*DATA_MEM_DATA_BITS-1:DATA_MEM_DATA_BITS] <= {uio_in, read_data_latch[7:0]};
                            end
                        end
                        4'd4: begin
                            if (active_is_write) begin
                                data_mem_write_ready[2] <= 1'b1;
                            end else begin
                                data_mem_read_ready[2] <= 1'b1;
                                data_mem_read_data_flat[3*DATA_MEM_DATA_BITS-1:2*DATA_MEM_DATA_BITS] <= {uio_in, read_data_latch[7:0]};
                            end
                        end
                        4'd5: begin
                            if (active_is_write) begin
                                data_mem_write_ready[3] <= 1'b1;
                            end else begin
                                data_mem_read_ready[3] <= 1'b1;
                                data_mem_read_data_flat[4*DATA_MEM_DATA_BITS-1:3*DATA_MEM_DATA_BITS] <= {uio_in, read_data_latch[7:0]};
                            end
                        end
                        default: ;
                    endcase
                    state <= STATE_IDLE;
                end
                default: state <= STATE_IDLE;
            endcase
        end
    end
endmodule
