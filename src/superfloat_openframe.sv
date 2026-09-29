`default_nettype none
`timescale 1ns/1ns

// SUPERFLOAT OPENFRAME — chip-level digital top (inside openframe_project_wrapper)
//
// 4 core tiles × 8 threads × one 8×8 SF16 systolic array = 256 MACs at 50 MHz.
// Program and data memory live on the host, reached through openframe_bus.
// A shared instruction cache (gpu.sv) serves all four tiles' fetches.
//
// Kernel launch:
//   1. Host loads program and data memory on its side.
//   2. Host drives the thread count on bus_in[7:0] and raises START.
//   3. The chip resets the GPU, writes the thread count, and runs.
//   4. DONE rises when every block has finished. Lowering START ends the
//      kernel and clears DONE; the next START rise launches a fresh kernel.
module superfloat_openframe #(
    parameter NUM_CORES = 4,
    parameter THREADS_PER_BLOCK = 8,
    parameter SYSTOLIC_SIZE = 8,
    parameter PROGRAM_MEM_ADDR_BITS = 9,
    parameter DATA_MEM_ADDR_BITS = 19,     // LSU addresses are 16-bit, zero-extended
    parameter BUS_BITS = 16,
    parameter PROGRAM_CACHE_ENTRIES = 32,  // shared instruction cache; 0 = one channel per tile
    parameter NUMBER_FORMAT = 0            // tile arithmetic: 0 SF16, 1 FP16, 2 BF16
) (
    input  wire clk,
    input  wire rst_n,                     // asynchronous, active low

    // Kernel control
    input  wire start,
    output wire done,
    output wire [NUM_CORES-1:0] core_active,

    // Memory bus (see openframe_bus.sv)
    output wire [BUS_BITS-1:0] bus_out,
    output wire                bus_sel,
    output wire                bus_we,
    output wire                bus_beat,
    output wire                bus_req,
    input  wire [BUS_BITS-1:0] bus_in,
    input  wire                bus_ack
);
    localparam NUM_PROG_CH = (PROGRAM_CACHE_ENTRIES > 0) ? 1 : NUM_CORES;
    localparam NUM_CH = NUM_PROG_CH + NUM_CORES;

    // ============================================
    // Reset: asynchronous assert, synchronous release
    // ============================================
    reg rst_s1, rst_s2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rst_s1 <= 1'b0;
            rst_s2 <= 1'b0;
        end else begin
            rst_s1 <= 1'b1;
            rst_s2 <= rst_s1;
        end
    end
    wire chip_reset = !rst_s2;

    // ============================================
    // Kernel launch sequencer
    // ============================================
    reg start_q1, start_q2;
    reg [7:0] thread_count_q;
    always @(posedge clk) begin
        if (chip_reset) begin
            start_q1 <= 1'b0;
            start_q2 <= 1'b0;
        end else begin
            start_q1 <= start;
            start_q2 <= start_q1;
        end
    end

    localparam [2:0] L_IDLE  = 3'd0,
                     L_RESET = 3'd1,   // hold the GPU in reset
                     L_WAIT  = 3'd2,   // let gpu's internal reset pipeline release
                     L_DCR   = 3'd3,   // write the thread count
                     L_RUN   = 3'd4;
    reg [2:0] launch_state;
    reg [2:0] launch_count;

    always @(posedge clk) begin
        if (chip_reset) begin
            launch_state   <= L_IDLE;
            launch_count   <= 3'd0;
            thread_count_q <= 8'd0;
        end else if (!start_q2) begin
            launch_state <= L_IDLE;
        end else begin
            case (launch_state)
                L_IDLE: begin
                    // bus_in is quiet between kernels: the host set it before START.
                    thread_count_q <= bus_in[7:0];
                    launch_count   <= 3'd0;
                    launch_state   <= L_RESET;
                end
                L_RESET: begin
                    launch_count <= launch_count + 3'd1;
                    if (launch_count == 3'd3) begin
                        launch_count <= 3'd0;
                        launch_state <= L_WAIT;
                    end
                end
                L_WAIT: begin
                    launch_count <= launch_count + 3'd1;
                    if (launch_count == 3'd3) launch_state <= L_DCR;
                end
                L_DCR:   launch_state <= L_RUN;
                default: launch_state <= L_RUN;
            endcase
        end
    end

    wire gpu_reset = chip_reset || (launch_state == L_IDLE) || (launch_state == L_RESET);
    wire gpu_start = (launch_state == L_RUN);
    wire dcr_we    = (launch_state == L_DCR);
    wire gpu_done;
    assign done = gpu_done && gpu_start;

    // ============================================
    // GPU
    // ============================================
    wire [NUM_PROG_CH-1:0]                       prog_valid;
    wire [PROGRAM_MEM_ADDR_BITS*NUM_PROG_CH-1:0] prog_addr_flat;
    wire [NUM_PROG_CH-1:0]                       prog_ready;
    wire [16*NUM_PROG_CH-1:0]                    prog_data_flat;

    wire [NUM_CORES-1:0]                    dread_valid;
    wire [DATA_MEM_ADDR_BITS*NUM_CORES-1:0] dread_addr_flat;
    wire [NUM_CORES-1:0]                    dread_ready;
    wire [16*NUM_CORES-1:0]                 dread_data_flat;
    wire [NUM_CORES-1:0]                    dwrite_valid;
    wire [DATA_MEM_ADDR_BITS*NUM_CORES-1:0] dwrite_addr_flat;
    wire [16*NUM_CORES-1:0]                 dwrite_data_flat;
    wire [NUM_CORES-1:0]                    dwrite_ready;

    gpu #(
        .DATA_MEM_ADDR_BITS(DATA_MEM_ADDR_BITS),
        .DATA_MEM_DATA_BITS(16),
        .DATA_MEM_NUM_CHANNELS(NUM_CORES),
        .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
        .PROGRAM_MEM_DATA_BITS(16),
        .PROGRAM_MEM_NUM_CHANNELS(NUM_PROG_CH),
        .PROGRAM_CACHE_ENTRIES(PROGRAM_CACHE_ENTRIES),
        .NUM_CORES(NUM_CORES),
        .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
        .SYSTOLIC_SIZE(SYSTOLIC_SIZE),
        .NUMBER_FORMAT(NUMBER_FORMAT)
    ) gpu_inst (
        .clk(clk),
        .reset(gpu_reset),
        .start(gpu_start),
        .done(gpu_done),
        .device_control_write_enable(dcr_we),
        .device_control_data(thread_count_q),

        .program_mem_read_valid(prog_valid),
        .program_mem_read_address_flat(prog_addr_flat),
        .program_mem_read_ready(prog_ready),
        .program_mem_read_data_flat(prog_data_flat),

        .data_mem_read_valid(dread_valid),
        .data_mem_read_address_flat(dread_addr_flat),
        .data_mem_read_ready(dread_ready),
        .data_mem_read_data_flat(dread_data_flat),
        .data_mem_write_valid(dwrite_valid),
        .data_mem_write_address_flat(dwrite_addr_flat),
        .data_mem_write_data_flat(dwrite_data_flat),
        .data_mem_write_ready(dwrite_ready),

        .core_active(core_active)
    );

    // ============================================
    // Channels -> pin bus (program channels first, then one data channel per tile)
    // ============================================
    wire [NUM_CH-1:0]          ch_read_valid  = {dread_valid, prog_valid};
    wire [NUM_CH-1:0]          ch_write_valid = {dwrite_valid, {NUM_PROG_CH{1'b0}}};
    wire [BUS_BITS*NUM_CH-1:0] ch_read_addr_flat;
    wire [BUS_BITS*NUM_CH-1:0] ch_write_addr_flat;
    wire [BUS_BITS*NUM_CH-1:0] ch_write_data_flat;
    wire [NUM_CH-1:0]          ch_read_ready;
    wire [NUM_CH-1:0]          ch_write_ready;
    wire [BUS_BITS-1:0]        ch_read_data;

    genvar c;
    generate
        for (c = 0; c < NUM_PROG_CH; c = c + 1) begin : program_channel_map
            assign ch_read_addr_flat[c*BUS_BITS +: BUS_BITS] =
                BUS_BITS'(prog_addr_flat[c*PROGRAM_MEM_ADDR_BITS +: PROGRAM_MEM_ADDR_BITS]);
            assign ch_write_addr_flat[c*BUS_BITS +: BUS_BITS] = {BUS_BITS{1'b0}};
            assign ch_write_data_flat[c*BUS_BITS +: BUS_BITS] = {BUS_BITS{1'b0}};
            assign prog_ready[c]              = ch_read_ready[c];
            assign prog_data_flat[c*16 +: 16] = ch_read_data;
        end
        for (c = 0; c < NUM_CORES; c = c + 1) begin : data_channel_map
            assign ch_read_addr_flat[(NUM_PROG_CH+c)*BUS_BITS +: BUS_BITS] =
                dread_addr_flat[c*DATA_MEM_ADDR_BITS +: BUS_BITS];
            assign ch_write_addr_flat[(NUM_PROG_CH+c)*BUS_BITS +: BUS_BITS] =
                dwrite_addr_flat[c*DATA_MEM_ADDR_BITS +: BUS_BITS];
            assign ch_write_data_flat[(NUM_PROG_CH+c)*BUS_BITS +: BUS_BITS] =
                dwrite_data_flat[c*16 +: 16];
            assign dread_ready[c]              = ch_read_ready[NUM_PROG_CH+c];
            assign dread_data_flat[c*16 +: 16] = ch_read_data;
            assign dwrite_ready[c]             = ch_write_ready[NUM_PROG_CH+c];
        end
    endgenerate

    openframe_bus #(
        .NUM_CHANNELS(NUM_CH),
        .NUM_PROGRAM_CHANNELS(NUM_PROG_CH),
        .BUS_BITS(BUS_BITS)
    ) bus (
        .clk(clk),
        .reset(chip_reset),
        .ch_read_valid(ch_read_valid),
        .ch_read_address_flat(ch_read_addr_flat),
        .ch_read_ready(ch_read_ready),
        .ch_read_data(ch_read_data),
        .ch_write_valid(ch_write_valid),
        .ch_write_address_flat(ch_write_addr_flat),
        .ch_write_data_flat(ch_write_data_flat),
        .ch_write_ready(ch_write_ready),
        .bus_out(bus_out),
        .bus_sel(bus_sel),
        .bus_we(bus_we),
        .bus_beat(bus_beat),
        .bus_req(bus_req),
        .bus_in(bus_in),
        .bus_ack(bus_ack)
    );
endmodule
