`default_nettype none
`timescale 1ns/1ns

// SHARED INSTRUCTION CACHE
// > Sits between the tiles' fetch ports and one external program channel.
// > Direct-mapped, ENTRIES words, one lookup at a time. A hit answers in
//   three cycles; a miss fetches the word once and fills the entry.
// > Every port waiting on the looked-up address is answered in the same
//   cycle, so tiles running one kernel pay for each instruction once.
// > reset invalidates every entry. The chip resets the GPU at each kernel
//   launch, so a program reloaded between launches is never served stale.
//
// Consumer protocol matches the controller: valid is held until a one-cycle
// ready pulse; data is valid with the pulse.
module shared_icache #(
    parameter NUM_PORTS = 4,
    parameter ADDR_BITS = 9,
    parameter DATA_BITS = 16,
    parameter ENTRIES = 32
) (
    input  wire clk,
    input  wire reset,

    input  wire [NUM_PORTS-1:0]           consumer_read_valid,
    input  wire [ADDR_BITS*NUM_PORTS-1:0] consumer_read_address_flat,
    output reg  [NUM_PORTS-1:0]           consumer_read_ready,
    output wire [DATA_BITS*NUM_PORTS-1:0] consumer_read_data_flat,

    output reg                  mem_read_valid,
    output reg  [ADDR_BITS-1:0] mem_read_address,
    input  wire                 mem_read_ready,
    input  wire [DATA_BITS-1:0] mem_read_data
);
    localparam INDEX_BITS = $clog2(ENTRIES);
    localparam TAG_BITS   = (ADDR_BITS > INDEX_BITS) ? ADDR_BITS - INDEX_BITS : 1;
    localparam PORT_BITS  = (NUM_PORTS > 1) ? $clog2(NUM_PORTS) : 1;

    localparam [1:0] S_PICK   = 2'd0,
                     S_LOOKUP = 2'd1,
                     S_FILL   = 2'd2,
                     S_DONE   = 2'd3;

    reg [DATA_BITS-1:0] data_mem [ENTRIES-1:0];
    reg [TAG_BITS-1:0]  tag_mem  [ENTRIES-1:0];
    reg [ENTRIES-1:0]   line_valid;

    reg [1:0]           state;
    reg [ADDR_BITS-1:0] cur_addr;
    reg [PORT_BITS-1:0] rr_next;
    reg [DATA_BITS-1:0] out_data;

    wire [ADDR_BITS-1:0] port_addr [NUM_PORTS-1:0];
    genvar gp;
    generate
        for (gp = 0; gp < NUM_PORTS; gp = gp + 1) begin : ports
            assign port_addr[gp] = consumer_read_address_flat[gp*ADDR_BITS +: ADDR_BITS];
            assign consumer_read_data_flat[gp*DATA_BITS +: DATA_BITS] = out_data;
        end
    endgenerate

    // Round-robin pick of a requesting port.
    reg                 found;
    reg [PORT_BITS-1:0] pick;
    integer k;
    always @(*) begin
        found = 1'b0;
        pick  = {PORT_BITS{1'b0}};
        for (k = 2 * NUM_PORTS - 1; k >= 0; k = k - 1) begin
            if (k >= rr_next && k < rr_next + NUM_PORTS && consumer_read_valid[k % NUM_PORTS]) begin
                found = 1'b1;
                pick  = PORT_BITS'(k % NUM_PORTS);
            end
        end
    end

    wire [INDEX_BITS-1:0] cur_index = cur_addr[INDEX_BITS-1:0];
    wire [TAG_BITS-1:0]   cur_tag   = (ADDR_BITS > INDEX_BITS) ? TAG_BITS'(cur_addr >> INDEX_BITS) : {TAG_BITS{1'b0}};
    wire hit = line_valid[cur_index] && (tag_mem[cur_index] == cur_tag);

    // Ports currently asking for cur_addr: all of them are answered together.
    reg [NUM_PORTS-1:0] waiting_on_cur;
    integer w;
    always @(*) begin
        for (w = 0; w < NUM_PORTS; w = w + 1)
            waiting_on_cur[w] = consumer_read_valid[w] && (port_addr[w] == cur_addr);
    end

    always @(posedge clk) begin
        if (reset) begin
            state               <= S_PICK;
            cur_addr            <= {ADDR_BITS{1'b0}};
            rr_next             <= {PORT_BITS{1'b0}};
            out_data            <= {DATA_BITS{1'b0}};
            line_valid          <= {ENTRIES{1'b0}};
            consumer_read_ready <= {NUM_PORTS{1'b0}};
            mem_read_valid      <= 1'b0;
            mem_read_address    <= {ADDR_BITS{1'b0}};
        end else begin
            consumer_read_ready <= {NUM_PORTS{1'b0}};
            case (state)
                S_PICK: begin
                    if (found) begin
                        cur_addr <= port_addr[pick];
                        rr_next  <= (pick == PORT_BITS'(NUM_PORTS - 1)) ? {PORT_BITS{1'b0}} : pick + 1'b1;
                        state    <= S_LOOKUP;
                    end
                end
                S_LOOKUP: begin
                    if (hit) begin
                        out_data            <= data_mem[cur_index];
                        consumer_read_ready <= waiting_on_cur;
                        state               <= S_DONE;
                    end else begin
                        mem_read_valid   <= 1'b1;
                        mem_read_address <= cur_addr;
                        state            <= S_FILL;
                    end
                end
                S_FILL: begin
                    if (mem_read_ready) begin
                        mem_read_valid         <= 1'b0;
                        data_mem[cur_index]    <= mem_read_data;
                        tag_mem[cur_index]     <= cur_tag;
                        line_valid[cur_index]  <= 1'b1;
                        out_data               <= mem_read_data;
                        consumer_read_ready    <= waiting_on_cur;
                        state                  <= S_DONE;
                    end
                end
                S_DONE: begin
                    // Answered ports drop valid on the edge that ends this
                    // cycle, so S_PICK never sees the same request twice.
                    state <= S_PICK;
                end
                default: state <= S_PICK;
            endcase
        end
    end
endmodule
