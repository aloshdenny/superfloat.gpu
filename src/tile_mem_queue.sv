`default_nettype none
`timescale 1ns/1ns

// TILE MEMORY QUEUE — a tile's LSU misses onto its one data channel, pipelined
//
// The consumers (the scratchpad's miss lines, one per LSU) hold valid until
// their one-cycle ready pulse, as before. The channel side separates taking a
// request from answering it:
//   - a request (read or write) is presented on mem_*_valid with its address
//     and data, and is taken in a cycle where mem_*_accept is high;
//   - reads are answered in the order they were taken, by a mem_read_ready
//     pulse with mem_read_data;
//   - a write is complete once taken (posted); its consumer's ready pulses the
//     cycle after.
// The next request is presented the cycle after one is taken, so a memory that
// takes requests early keeps several reads in flight. One that only accepts
// with its answer (mem_*_accept = mem_*_ready) sees one request at a time, as
// with the controller this replaces.
module tile_mem_queue #(
    parameter ADDR_BITS = 16,
    parameter DATA_BITS = 16,
    parameter NUM_CONSUMERS = 8
) (
    input wire clk,
    input wire reset,

    input  wire [NUM_CONSUMERS-1:0]           consumer_read_valid,
    input  wire [ADDR_BITS*NUM_CONSUMERS-1:0] consumer_read_address_flat,
    output reg  [NUM_CONSUMERS-1:0]           consumer_read_ready,
    output wire [DATA_BITS*NUM_CONSUMERS-1:0] consumer_read_data_flat,
    input  wire [NUM_CONSUMERS-1:0]           consumer_write_valid,
    input  wire [ADDR_BITS*NUM_CONSUMERS-1:0] consumer_write_address_flat,
    input  wire [DATA_BITS*NUM_CONSUMERS-1:0] consumer_write_data_flat,
    output reg  [NUM_CONSUMERS-1:0]           consumer_write_ready,

    output reg                  mem_read_valid,
    output reg  [ADDR_BITS-1:0] mem_read_address,
    input  wire                 mem_read_accept,
    input  wire                 mem_read_ready,
    input  wire [DATA_BITS-1:0] mem_read_data,
    output reg                  mem_write_valid,
    output reg  [ADDR_BITS-1:0] mem_write_address,
    output reg  [DATA_BITS-1:0] mem_write_data,
    input  wire                 mem_write_accept
);
    localparam ID_BITS = (NUM_CONSUMERS > 1) ? $clog2(NUM_CONSUMERS) : 1;

    // A consumer is issued from the cycle it enters the slot until its valid drops.
    reg [NUM_CONSUMERS-1:0] issued;
    wire [NUM_CONSUMERS-1:0] pending = (consumer_read_valid | consumer_write_valid) & ~issued;

    // Slot: the request on the channel (registered outputs).
    reg               slot_valid, slot_we;
    reg [ID_BITS-1:0] slot_id;
    wire slot_taken = slot_valid & (slot_we ? mem_write_accept : mem_read_accept);

    // In-order ids of the reads taken and not yet answered.
    reg [ID_BITS-1:0] order [NUM_CONSUMERS-1:0];
    reg [ID_BITS-1:0] rd_ptr, wr_ptr;
    reg [ID_BITS:0]   count;
    wire push = slot_taken & ~slot_we;
    // An answer may come in the cycle its read is taken (accept = ready): it
    // then bypasses the queue.
    wire [ID_BITS-1:0] head_id = (count == 0) ? slot_id : order[rd_ptr];
    wire bypass = mem_read_ready & (count == 0);
    wire push_q = push & ~bypass;
    wire pop_q  = mem_read_ready & (count != 0);

    reg [DATA_BITS-1:0] rdata [NUM_CONSUMERS-1:0];
    genvar gc;
    generate
        for (gc = 0; gc < NUM_CONSUMERS; gc = gc + 1) begin : data_out
            assign consumer_read_data_flat[gc*DATA_BITS +: DATA_BITS] = rdata[gc];
        end
    endgenerate

    // Round-robin pick among pending consumers.
    reg [ID_BITS-1:0] rr;
    reg               found;
    reg [ID_BITS-1:0] pick;
    integer k;
    always @(*) begin
        found = 1'b0;
        pick  = {ID_BITS{1'b0}};
        for (k = 2 * NUM_CONSUMERS - 1; k >= 0; k = k - 1) begin
            if (k >= rr && k < rr + NUM_CONSUMERS && pending[k % NUM_CONSUMERS]) begin
                found = 1'b1;
                pick  = ID_BITS'(k % NUM_CONSUMERS);
            end
        end
    end

    integer i;
    always @(posedge clk) begin
        if (reset) begin
            issued               <= {NUM_CONSUMERS{1'b0}};
            slot_valid           <= 1'b0;
            slot_we              <= 1'b0;
            slot_id              <= {ID_BITS{1'b0}};
            mem_read_valid       <= 1'b0;
            mem_write_valid      <= 1'b0;
            mem_read_address     <= {ADDR_BITS{1'b0}};
            mem_write_address    <= {ADDR_BITS{1'b0}};
            mem_write_data       <= {DATA_BITS{1'b0}};
            consumer_read_ready  <= {NUM_CONSUMERS{1'b0}};
            consumer_write_ready <= {NUM_CONSUMERS{1'b0}};
            rd_ptr               <= {ID_BITS{1'b0}};
            wr_ptr               <= {ID_BITS{1'b0}};
            count                <= {(ID_BITS+1){1'b0}};
            rr                   <= {ID_BITS{1'b0}};
            for (i = 0; i < NUM_CONSUMERS; i = i + 1) rdata[i] <= {DATA_BITS{1'b0}};
        end else begin
            consumer_read_ready  <= {NUM_CONSUMERS{1'b0}};
            consumer_write_ready <= {NUM_CONSUMERS{1'b0}};

            // A consumer is free again once it has dropped valid after its ready.
            for (i = 0; i < NUM_CONSUMERS; i = i + 1)
                if (!consumer_read_valid[i] && !consumer_write_valid[i] && !(slot_valid && slot_id == ID_BITS'(i)))
                    issued[i] <= 1'b0;

            // Taken: writes complete now, reads join the answer order.
            if (slot_taken && slot_we)
                consumer_write_ready[slot_id] <= 1'b1;
            if (push_q) begin
                order[wr_ptr] <= slot_id;
                wr_ptr        <= wr_ptr + 1'b1;
            end

            // Answers, in order.
            if (mem_read_ready) begin
                consumer_read_ready[head_id] <= 1'b1;
                rdata[head_id]               <= mem_read_data;
            end
            if (pop_q) rd_ptr <= rd_ptr + 1'b1;
            count <= count + {{ID_BITS{1'b0}}, push_q} - {{ID_BITS{1'b0}}, pop_q};

            // Refill the slot the cycle it is taken, or while it is empty.
            if (!slot_valid || slot_taken) begin
                slot_valid      <= found;
                mem_read_valid  <= found & ~consumer_write_valid[pick];
                mem_write_valid <= found &  consumer_write_valid[pick];
                if (found) begin
                    slot_id           <= pick;
                    slot_we           <= consumer_write_valid[pick];
                    issued[pick]      <= 1'b1;
                    rr                <= (pick == ID_BITS'(NUM_CONSUMERS - 1)) ? {ID_BITS{1'b0}} : pick + 1'b1;
                    mem_read_address  <= consumer_read_address_flat[pick*ADDR_BITS +: ADDR_BITS];
                    mem_write_address <= consumer_write_address_flat[pick*ADDR_BITS +: ADDR_BITS];
                    mem_write_data    <= consumer_write_data_flat[pick*DATA_BITS +: DATA_BITS];
                end
            end
        end
    end
endmodule

`default_nettype wire
