`default_nettype none
`timescale 1ns/1ns

// OPENFRAME PIN BUS — external program/data memory over GPIO
//
// Serves NUM_CHANNELS internal memory channels (program channels first, then
// data channels) over a 16-bit out bus and a 16-bit in bus. The chip is the
// bus master; the host holds program and data memory. SEL is 0 for program
// memory, 1 for data memory. The mode is chosen per launch (sync_mode, latched
// with the thread count) and must not change while a kernel runs.
//
// Async mode: one transaction at a time, two-phase handshake. The chip toggles
// REQ, the host answers by making ACK equal to REQ. ACK passes through a
// two-flop synchronizer, so the host may run on its own clock. Every output is
// registered and settles one cycle before REQ toggles. After reset REQ=0 and
// the host must hold ACK=0. IN must be stable before the host changes ACK and
// stay stable until REQ toggles again.
//   Read  (1 beat):  OUT=address, SEL, WE=0, BEAT=0, toggle REQ
//                    host puts the word on IN, then sets ACK=REQ
//   Write (2 beats): OUT=address, SEL, WE=1, BEAT=0, toggle REQ; wait ACK=REQ
//                    OUT=data,             BEAT=1, toggle REQ; wait ACK=REQ
// The next transaction is set up in the cycle the previous one completes.
//
// Sync mode: the host runs on the chip's clock (it drives it) and samples the
// outputs at each rising edge. REQ is a level: each cycle with REQ=1 is one
// beat.
//   Read:  REQ=1, WE=0, OUT=address. The host answers every read in order,
//          any number of cycles later, by driving the word on IN with ACK=1
//          for one cycle. At most OUTSTANDING reads are in flight.
//   Write: REQ=1, WE=1, BEAT=0, OUT=address, then the next cycle REQ=1,
//          WE=1, BEAT=1, OUT=data. Writes are not answered.
// The host takes a beat every cycle. A read of the same word (SEL and
// address) as the newest read in flight joins it instead of using a beat, and
// its answer goes to both channels: tiles running in step share their reads.
// IN and ACK are registered at the pins.
//
// Channels: a program channel holds valid until its ready pulse and has one
// read at a time. A data channel (tile_mem_queue) presents its next request
// the cycle after a read's ch_read_accept or a write's ch_write_ready; its
// reads are answered by ch_read_ready in order. In async mode a read is
// accepted when it is answered.
module openframe_bus #(
    parameter NUM_CHANNELS = 5,
    parameter NUM_PROGRAM_CHANNELS = 1,
    parameter BUS_BITS = 16,
    parameter OUTSTANDING = 8                  // sync mode: reads in flight (power of 2)
) (
    input  wire clk,
    input  wire reset,
    input  wire sync_mode,

    input  wire [NUM_CHANNELS-1:0]          ch_read_valid,
    input  wire [BUS_BITS*NUM_CHANNELS-1:0] ch_read_address_flat,
    output reg  [NUM_CHANNELS-1:0]          ch_read_accept,
    output reg  [NUM_CHANNELS-1:0]          ch_read_ready,
    output wire [BUS_BITS-1:0]              ch_read_data,      // shared, valid with the ready pulses
    input  wire [NUM_CHANNELS-1:0]          ch_write_valid,
    input  wire [BUS_BITS*NUM_CHANNELS-1:0] ch_write_address_flat,
    input  wire [BUS_BITS*NUM_CHANNELS-1:0] ch_write_data_flat,
    output reg  [NUM_CHANNELS-1:0]          ch_write_ready,    // write taken (complete)

    output reg  [BUS_BITS-1:0] bus_out,
    output reg                 bus_sel,
    output reg                 bus_we,
    output reg                 bus_beat,
    output reg                 bus_req,
    input  wire [BUS_BITS-1:0] bus_in,
    input  wire                bus_ack
);
    localparam CH_BITS = (NUM_CHANNELS > 1) ? $clog2(NUM_CHANNELS) : 1;
    localparam Q_BITS  = $clog2(OUTSTANDING);
    localparam [NUM_CHANNELS-1:0] PROG_MASK = (1 << NUM_PROGRAM_CHANNELS) - 1;

    localparam [2:0] A_IDLE      = 3'd0,
                     A_ADDR      = 3'd1,
                     A_ADDR_WAIT = 3'd2,
                     A_DATA      = 3'd3,
                     A_DATA_WAIT = 3'd4;

    reg [2:0]          a_state;
    reg [CH_BITS-1:0]  cur;
    reg [CH_BITS-1:0]  rr;                     // round-robin start
    reg                ack_q1, ack_q2;
    reg [BUS_BITS-1:0] in_q;                   // IN, registered (sync mode)
    reg [BUS_BITS-1:0] rdata;
    assign ch_read_data = rdata;

    // A channel taken (or answered, for a program channel) in the last cycle
    // still shows that request; a program channel's read is in flight until
    // answered.
    reg [NUM_CHANNELS-1:0] taken_q, busy;

    // Sync mode: reads in flight, oldest first; each answers a set of channels.
    reg [NUM_CHANNELS-1:0] q_mask [OUTSTANDING-1:0];
    reg [Q_BITS-1:0]       q_rd, q_wr;
    reg [Q_BITS:0]         q_count;
    reg [BUS_BITS-1:0]     last_addr;          // newest read in flight
    reg                    last_sel;
    reg                    w_beat;             // write data beat due
    reg [CH_BITS-1:0]      w_ch;
    reg [BUS_BITS-1:0]     w_data;

    wire [NUM_CHANNELS-1:0] requesting = ch_read_valid | ch_write_valid;
    wire q_full  = (q_count == OUTSTANDING);
    wire answer  = sync_mode & ack_q1;          // a sync read's answer is on in_q
    wire [NUM_CHANNELS-1:0] cur_mask = (a_state == A_IDLE) ? {NUM_CHANNELS{1'b0}}
                                                           : (NUM_CHANNELS'(1) << cur);
    // Eligible: requesting, not just taken, no read of its own in flight
    // (program channels), not the async transaction in progress, and room for
    // a read in sync mode.
    wire [NUM_CHANNELS-1:0] eligible = requesting & ~taken_q & ~busy & ~cur_mask &
                                       (ch_write_valid | {NUM_CHANNELS{~(sync_mode & q_full)}});

    reg               found;
    reg [CH_BITS-1:0] pick;
    integer k;
    always @(*) begin
        found = 1'b0;
        pick  = {CH_BITS{1'b0}};
        for (k = 2 * NUM_CHANNELS - 1; k >= 0; k = k - 1) begin
            if (k >= rr && k < rr + NUM_CHANNELS && eligible[k % NUM_CHANNELS]) begin
                found = 1'b1;
                pick  = CH_BITS'(k % NUM_CHANNELS);
            end
        end
    end

    wire                pick_we    = ch_write_valid[pick];
    wire                pick_sel   = (pick >= NUM_PROGRAM_CHANNELS);
    wire [BUS_BITS-1:0] pick_raddr = ch_read_address_flat[pick*BUS_BITS +: BUS_BITS];
    wire [BUS_BITS-1:0] pick_waddr = ch_write_address_flat[pick*BUS_BITS +: BUS_BITS];
    wire [BUS_BITS-1:0] pick_wdata = ch_write_data_flat[pick*BUS_BITS +: BUS_BITS];
    wire acked = (ack_q2 == bus_req);
    // Join the newest read in flight, unless it is answered this cycle.
    wire joins_newest = (q_count != 0) && !(answer && q_count == 1) &&
                (last_sel == pick_sel) && (last_addr == pick_raddr);
    wire [Q_BITS-1:0] q_newest = q_wr - 1'b1;

    integer i;
    always @(posedge clk) begin
        if (reset) begin
            a_state        <= A_IDLE;
            cur            <= {CH_BITS{1'b0}};
            rr             <= {CH_BITS{1'b0}};
            ack_q1         <= 1'b0;
            ack_q2         <= 1'b0;
            in_q           <= {BUS_BITS{1'b0}};
            rdata          <= {BUS_BITS{1'b0}};
            taken_q        <= {NUM_CHANNELS{1'b0}};
            busy           <= {NUM_CHANNELS{1'b0}};
            q_rd           <= {Q_BITS{1'b0}};
            q_wr           <= {Q_BITS{1'b0}};
            q_count        <= {(Q_BITS+1){1'b0}};
            last_addr      <= {BUS_BITS{1'b0}};
            last_sel       <= 1'b0;
            w_beat         <= 1'b0;
            w_ch           <= {CH_BITS{1'b0}};
            w_data         <= {BUS_BITS{1'b0}};
            ch_read_accept <= {NUM_CHANNELS{1'b0}};
            ch_read_ready  <= {NUM_CHANNELS{1'b0}};
            ch_write_ready <= {NUM_CHANNELS{1'b0}};
            bus_out        <= {BUS_BITS{1'b0}};
            bus_sel        <= 1'b0;
            bus_we         <= 1'b0;
            bus_beat       <= 1'b0;
            bus_req        <= 1'b0;
        end else begin
            ack_q1 <= bus_ack;
            ack_q2 <= ack_q1;
            in_q   <= bus_in;
            ch_read_accept <= {NUM_CHANNELS{1'b0}};
            ch_read_ready  <= {NUM_CHANNELS{1'b0}};
            ch_write_ready <= {NUM_CHANNELS{1'b0}};
            taken_q        <= {NUM_CHANNELS{1'b0}};

            if (!sync_mode) begin
                // ---------------- async: one handshake at a time ----------------
                case (a_state)
                    A_IDLE: begin
                        if (found) begin
                            cur      <= pick;
                            rr       <= (pick == CH_BITS'(NUM_CHANNELS - 1)) ? {CH_BITS{1'b0}} : pick + 1'b1;
                            bus_sel  <= pick_sel;
                            bus_we   <= pick_we;
                            bus_beat <= 1'b0;
                            bus_out  <= pick_we ? pick_waddr : pick_raddr;
                            a_state  <= A_ADDR;
                        end
                    end
                    A_ADDR: begin
                        bus_req <= ~bus_req;
                        a_state <= A_ADDR_WAIT;
                    end
                    A_DATA: begin
                        bus_req <= ~bus_req;
                        a_state <= A_DATA_WAIT;
                    end
                    A_ADDR_WAIT, A_DATA_WAIT: begin
                        if (acked && a_state == A_ADDR_WAIT && bus_we) begin
                            bus_out  <= ch_write_data_flat[cur*BUS_BITS +: BUS_BITS];
                            bus_beat <= 1'b1;
                            a_state  <= A_DATA;
                        end else if (acked) begin
                            if (bus_we) begin
                                ch_write_ready[cur] <= 1'b1;
                            end else begin
                                rdata               <= bus_in;
                                ch_read_ready[cur]  <= 1'b1;
                                ch_read_accept[cur] <= 1'b1;
                            end
                            taken_q[cur] <= 1'b1;
                            // the next transaction starts now
                            if (found) begin
                                cur      <= pick;
                                rr       <= (pick == CH_BITS'(NUM_CHANNELS - 1)) ? {CH_BITS{1'b0}} : pick + 1'b1;
                                bus_sel  <= pick_sel;
                                bus_we   <= pick_we;
                                bus_beat <= 1'b0;
                                bus_out  <= pick_we ? pick_waddr : pick_raddr;
                                a_state  <= A_ADDR;
                            end else begin
                                a_state  <= A_IDLE;
                            end
                        end
                    end
                    default: a_state <= A_IDLE;
                endcase
            end else begin
                // ---------------- sync: a beat every cycle ----------------
                bus_req <= 1'b0;

                // Answers, oldest read first.
                if (answer) begin
                    rdata         <= in_q;
                    ch_read_ready <= q_mask[q_rd];
                    busy          <= busy & ~q_mask[q_rd];
                    taken_q       <= q_mask[q_rd] & PROG_MASK;    // program channels drop valid next
                    q_rd          <= q_rd + 1'b1;
                end

                if (w_beat) begin
                    bus_out        <= w_data;
                    bus_we         <= 1'b1;
                    bus_beat       <= 1'b1;
                    bus_req        <= 1'b1;
                    w_beat         <= 1'b0;
                    ch_write_ready[w_ch] <= 1'b1;
                    taken_q[w_ch]  <= 1'b1;
                end else if (found) begin
                    rr <= (pick == CH_BITS'(NUM_CHANNELS - 1)) ? {CH_BITS{1'b0}} : pick + 1'b1;
                    if (pick_we) begin
                        bus_out  <= pick_waddr;
                        bus_sel  <= 1'b1;
                        bus_we   <= 1'b1;
                        bus_beat <= 1'b0;
                        bus_req  <= 1'b1;
                        w_beat   <= 1'b1;
                        w_ch     <= pick;
                        w_data   <= pick_wdata;
                    end else begin
                        if (joins_newest) begin
                            q_mask[q_newest][pick] <= 1'b1;
                        end else begin
                            bus_out       <= pick_raddr;
                            bus_sel       <= pick_sel;
                            bus_we        <= 1'b0;
                            bus_beat      <= 1'b0;
                            bus_req       <= 1'b1;
                            q_mask[q_wr]  <= NUM_CHANNELS'(1) << pick;
                            q_wr          <= q_wr + 1'b1;
                            last_addr     <= pick_raddr;
                            last_sel      <= pick_sel;
                        end
                        ch_read_accept[pick] <= 1'b1;
                        taken_q[pick]        <= 1'b1;
                        if (PROG_MASK[pick]) busy[pick] <= 1'b1;
                    end
                end

                q_count <= q_count + {{Q_BITS{1'b0}}, (found && !w_beat && !pick_we && !joins_newest)}
                                   - {{Q_BITS{1'b0}}, answer};
            end
        end
    end
endmodule

`default_nettype wire
