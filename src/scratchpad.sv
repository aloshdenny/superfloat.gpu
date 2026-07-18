`default_nettype none
`timescale 1ns/1ns

// Address-mapped 128B on-die scratchpad bridge for Tiny Tapeout RAM32 (32×32 1RW).
// Maps the top 64 SF16 halfwords (addr 0xFFC0..0xFFFF) onto the macro.
// Hits stay on-die; misses pass through to the external data controller.
module scratchpad #(
    parameter ADDR_BITS = 19,
    parameter DATA_BITS = 16,
    parameter NUM_PORTS = 4,
    // Top 64 halfwords — within 16-bit LSU address space from rs
    parameter [ADDR_BITS-1:0] BASE_ADDR = 19'h0FFC0
) (
    input  wire                              clk,
    input  wire                              reset,

    // LSU side
    input  wire [NUM_PORTS-1:0]              consumer_read_valid,
    input  wire [ADDR_BITS*NUM_PORTS-1:0]    consumer_read_address_flat,
    output wire [NUM_PORTS-1:0]              consumer_read_ready,
    output wire [DATA_BITS*NUM_PORTS-1:0]    consumer_read_data_flat,
    input  wire [NUM_PORTS-1:0]              consumer_write_valid,
    input  wire [ADDR_BITS*NUM_PORTS-1:0]    consumer_write_address_flat,
    input  wire [DATA_BITS*NUM_PORTS-1:0]    consumer_write_data_flat,
    output wire [NUM_PORTS-1:0]              consumer_write_ready,

    // External data-memory side (misses)
    output wire [NUM_PORTS-1:0]              mem_read_valid,
    output wire [ADDR_BITS*NUM_PORTS-1:0]    mem_read_address_flat,
    input  wire [NUM_PORTS-1:0]              mem_read_ready,
    input  wire [DATA_BITS*NUM_PORTS-1:0]    mem_read_data_flat,
    output wire [NUM_PORTS-1:0]              mem_write_valid,
    output wire [ADDR_BITS*NUM_PORTS-1:0]    mem_write_address_flat,
    output wire [DATA_BITS*NUM_PORTS-1:0]    mem_write_data_flat,
    input  wire [NUM_PORTS-1:0]              mem_write_ready,

    // RAM32 1RW ports (instance lives at chip top as ram1)
    output wire                              ram_en,
    output wire [3:0]                        ram_we,
    output wire [4:0]                        ram_addr,
    output wire [31:0]                       ram_di,
    input  wire [31:0]                       ram_do
);
    localparam OFFSET_BITS = 6; // 64 halfwords
    localparam ST_IDLE        = 2'd0;
    localparam ST_READ_ISSUE  = 2'd1;
    localparam ST_READ_DATA   = 2'd2;
    localparam ST_WRITE       = 2'd3;

    wire [ADDR_BITS-1:0] c_raddr [NUM_PORTS-1:0];
    wire [ADDR_BITS-1:0] c_waddr [NUM_PORTS-1:0];
    wire [DATA_BITS-1:0] c_wdata [NUM_PORTS-1:0];
    wire [DATA_BITS-1:0] m_rdata [NUM_PORTS-1:0];

    wire [NUM_PORTS-1:0] read_hit;
    wire [NUM_PORTS-1:0] write_hit;

    genvar gi;
    generate
        for (gi = 0; gi < NUM_PORTS; gi = gi + 1) begin : unpack
            assign c_raddr[gi] = consumer_read_address_flat[gi*ADDR_BITS +: ADDR_BITS];
            assign c_waddr[gi] = consumer_write_address_flat[gi*ADDR_BITS +: ADDR_BITS];
            assign c_wdata[gi] = consumer_write_data_flat[gi*DATA_BITS +: DATA_BITS];
            assign m_rdata[gi] = mem_read_data_flat[gi*DATA_BITS +: DATA_BITS];
            assign read_hit[gi]  = consumer_read_valid[gi]  && (c_raddr[gi] >= BASE_ADDR);
            assign write_hit[gi] = consumer_write_valid[gi] && (c_waddr[gi] >= BASE_ADDR);
        end
    endgenerate

    // Misses go off-chip unchanged
    assign mem_read_valid         = consumer_read_valid & ~read_hit;
    assign mem_read_address_flat  = consumer_read_address_flat;
    assign mem_write_valid        = consumer_write_valid & ~write_hit;
    assign mem_write_address_flat = consumer_write_address_flat;
    assign mem_write_data_flat    = consumer_write_data_flat;

    reg [1:0]                       state;
    reg [$clog2(NUM_PORTS)-1:0]     sel;
    reg [OFFSET_BITS-1:0]           sel_offset;
    reg [DATA_BITS-1:0]             sel_wdata;

    reg [NUM_PORTS-1:0]             hit_read_ready;
    reg [NUM_PORTS-1:0]             hit_write_ready;
    reg [DATA_BITS-1:0]             hit_rdata [NUM_PORTS-1:0];

    integer i;
    reg found;
    reg [$clog2(NUM_PORTS)-1:0] pick;
    reg                         pick_write;
    reg [OFFSET_BITS-1:0]       pick_offset;
    reg [DATA_BITS-1:0]         pick_wdata;

    // Priority grant among outstanding hits (writes before reads)
    always @(*) begin
        found = 1'b0;
        pick = {$clog2(NUM_PORTS){1'b0}};
        pick_write = 1'b0;
        pick_offset = {OFFSET_BITS{1'b0}};
        pick_wdata = {DATA_BITS{1'b0}};
        for (i = 0; i < NUM_PORTS; i = i + 1) begin
            if (!found && write_hit[i]) begin
                found = 1'b1;
                pick = i[$clog2(NUM_PORTS)-1:0];
                pick_write = 1'b1;
                pick_offset = c_waddr[i][OFFSET_BITS-1:0];
                pick_wdata = c_wdata[i];
            end
        end
        for (i = 0; i < NUM_PORTS; i = i + 1) begin
            if (!found && read_hit[i]) begin
                found = 1'b1;
                pick = i[$clog2(NUM_PORTS)-1:0];
                pick_write = 1'b0;
                pick_offset = c_raddr[i][OFFSET_BITS-1:0];
                pick_wdata = {DATA_BITS{1'b0}};
            end
        end
    end

    wire issuing = (state == ST_READ_ISSUE) || (state == ST_WRITE);

    assign ram_en   = issuing || (state == ST_READ_DATA);
    assign ram_addr = sel_offset[OFFSET_BITS-1:1];
    assign ram_we   = (state == ST_WRITE)
                        ? (sel_offset[0] ? 4'b1100 : 4'b0011)
                        : 4'b0000;
    assign ram_di   = sel_offset[0] ? {sel_wdata, 16'h0000} : {16'h0000, sel_wdata};

    always @(posedge clk) begin
        if (reset) begin
            state <= ST_IDLE;
            sel <= {$clog2(NUM_PORTS){1'b0}};
            sel_offset <= {OFFSET_BITS{1'b0}};
            sel_wdata <= {DATA_BITS{1'b0}};
            hit_read_ready <= {NUM_PORTS{1'b0}};
            hit_write_ready <= {NUM_PORTS{1'b0}};
            for (i = 0; i < NUM_PORTS; i = i + 1)
                hit_rdata[i] <= {DATA_BITS{1'b0}};
        end else begin
            hit_read_ready <= {NUM_PORTS{1'b0}};
            hit_write_ready <= {NUM_PORTS{1'b0}};

            case (state)
                ST_IDLE: begin
                    if (found) begin
                        sel <= pick;
                        sel_offset <= pick_offset;
                        sel_wdata <= pick_wdata;
                        state <= pick_write ? ST_WRITE : ST_READ_ISSUE;
                    end
                end
                ST_READ_ISSUE: begin
                    // EN/A0 stable this cycle; RAM updates Do0 on next edge
                    state <= ST_READ_DATA;
                end
                ST_READ_DATA: begin
                    hit_rdata[sel] <= sel_offset[0] ? ram_do[31:16] : ram_do[15:0];
                    hit_read_ready[sel] <= 1'b1;
                    state <= ST_IDLE;
                end
                ST_WRITE: begin
                    // EN/WE stable this cycle; write commits on this edge
                    hit_write_ready[sel] <= 1'b1;
                    state <= ST_IDLE;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end

    generate
        for (gi = 0; gi < NUM_PORTS; gi = gi + 1) begin : ready_mux
            assign consumer_read_ready[gi] =
                read_hit[gi] ? hit_read_ready[gi] : mem_read_ready[gi];
            assign consumer_write_ready[gi] =
                write_hit[gi] ? hit_write_ready[gi] : mem_write_ready[gi];
            assign consumer_read_data_flat[gi*DATA_BITS +: DATA_BITS] =
                read_hit[gi] ? hit_rdata[gi] : m_rdata[gi];
        end
    endgenerate
endmodule
