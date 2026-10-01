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
// its answer goes to every channel that asked: tiles running in step share
// their reads. IN and ACK are registered at the pins.
//
// Shared reads (sync, SHARE_LINES > 0). The answers to data reads are kept in
// SHARE_LINES lines of 8 words (aligned groups of 8 addresses), oldest line
// replaced first. A data channel whose next read finds its word there is
// answered from it instead of the pins, one channel per cycle, alongside the
// bus: tiles that read the same words some cycles apart (activations shared
// by every block) read them from the pins once. A channel is answered this way
// only with none of its reads in flight, so its answers stay in order; until
// then the read waits, off the bus, while its word is in the lines. Any
// write empties the lines, and reads issued before it do not fill them; so
// does `flush`, which the chip raises between launches.
//
// Channels. A program channel holds valid until its ready pulse and has one
// read at a time. A data channel (tile_mem_queue) hands over a request in a
// cycle where its ch_read_accept (reads) or ch_write_ready (writes) is high,
// and presents the next one the cycle after; its reads are answered by
// ch_read_ready, in order.
//   - Async: accept / ch_write_ready pulse when the transaction completes.
//   - Sync: they mean "room for a request this cycle". Each data channel has
//     a two-entry buffer here, so a tile can hand over a request every cycle,
//     and the tiles' requests are registered before the pick.
module openframe_bus #(
    parameter NUM_CHANNELS = 5,
    parameter NUM_PROGRAM_CHANNELS = 1,
    parameter BUS_BITS = 16,
    parameter OUTSTANDING = 8,                 // sync mode: reads in flight (power of 2)
    parameter STICKY = 1,                      // sync mode: keep serving a channel while it has requests (tiles then take turns)
    parameter SHARE_LINES = 8                  // sync mode: lines of recent data answers (0 = none)
) (
    input  wire clk,
    input  wire reset,
    input  wire sync_mode,
    input  wire flush,                         // empty the shared-read lines (memory changed)

    input  wire [NUM_CHANNELS-1:0]          ch_read_valid,
    input  wire [BUS_BITS*NUM_CHANNELS-1:0] ch_read_address_flat,
    output wire [NUM_CHANNELS-1:0]          ch_read_accept,
    output reg  [NUM_CHANNELS-1:0]          ch_read_ready,
    output wire [BUS_BITS*NUM_CHANNELS-1:0] ch_read_data_flat, // valid with the ready pulses
    input  wire [NUM_CHANNELS-1:0]          ch_write_valid,
    input  wire [BUS_BITS*NUM_CHANNELS-1:0] ch_write_address_flat,
    input  wire [BUS_BITS*NUM_CHANNELS-1:0] ch_write_data_flat,
    output wire [NUM_CHANNELS-1:0]          ch_write_ready,    // write taken (complete)

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
    // Shared-read answers come on their own path (share_data, shared_q).
    reg [NUM_CHANNELS-1:0] shared_q;
    reg [BUS_BITS-1:0]     share_data;
    genvar gch;
    generate
        for (gch = 0; gch < NUM_CHANNELS; gch = gch + 1) begin : read_data_out
            assign ch_read_data_flat[gch*BUS_BITS +: BUS_BITS] = shared_q[gch] ? share_data : rdata;
        end
    endgenerate

    // Async completion pulses, and the sync "room" signal of each data channel.
    reg [NUM_CHANNELS-1:0] a_accept, a_wready, room;
    assign ch_read_accept = sync_mode ? (room & ~PROG_MASK) : a_accept;
    assign ch_write_ready = sync_mode ? (room & ~PROG_MASK) : a_wready;

    // A program channel answered (or, async, any channel served) in the last
    // cycle still shows that request; a program channel's sync read is in
    // flight until answered.
    reg [NUM_CHANNELS-1:0] taken_q, busy;

    // Sync mode: each data channel's two-entry request buffer, entry 0 first.
    reg [1:0]          b_cnt   [NUM_CHANNELS-1:0];
    reg                b0_we   [NUM_CHANNELS-1:0];
    reg                b1_we   [NUM_CHANNELS-1:0];
    reg [BUS_BITS-1:0] b0_addr [NUM_CHANNELS-1:0];
    reg [BUS_BITS-1:0] b1_addr [NUM_CHANNELS-1:0];
    reg [BUS_BITS-1:0] b0_data [NUM_CHANNELS-1:0];
    reg [BUS_BITS-1:0] b1_data [NUM_CHANNELS-1:0];

    // Sync mode: reads in flight, oldest first; each answers a set of channels.
    reg [NUM_CHANNELS-1:0] q_mask [OUTSTANDING-1:0];
    reg [Q_BITS-1:0]       q_rd, q_wr;
    reg [Q_BITS:0]         q_count;
    reg [BUS_BITS-1:0]     last_addr;          // newest read in flight
    reg                    last_sel;
    reg [BUS_BITS-1:0]     q_addr  [OUTSTANDING-1:0];
    reg                    q_sel   [OUTSTANDING-1:0];
    reg [OUTSTANDING-1:0]  q_stale;            // issued before a write: neither joined nor kept
    reg [Q_BITS:0]         rcnt    [NUM_CHANNELS-1:0];   // each channel's reads in flight
    reg                    w_beat;             // write data beat due
    reg [BUS_BITS-1:0]     w_data;

    wire q_full = (q_count == OUTSTANDING);
    wire answer = sync_mode & ack_q1;           // a sync read's answer is on in_q

    // Each channel's request as the pick sees it: the inputs (async, and
    // program channels), or the head of the data channel's buffer (sync).
    reg [NUM_CHANNELS-1:0] r_valid, r_we;
    reg [BUS_BITS-1:0]     r_addr [NUM_CHANNELS-1:0];
    reg [BUS_BITS-1:0]     r_data [NUM_CHANNELS-1:0];
    // The incoming request on each channel (what a buffer takes).
    reg [BUS_BITS-1:0]     in_addr [NUM_CHANNELS-1:0];
    integer c;
    always @(*) begin
        for (c = 0; c < NUM_CHANNELS; c = c + 1) begin
            in_addr[c] = ch_write_valid[c] ? ch_write_address_flat[c*BUS_BITS +: BUS_BITS]
                                           : ch_read_address_flat[c*BUS_BITS +: BUS_BITS];
            if (sync_mode && !PROG_MASK[c]) begin
                r_valid[c] = (b_cnt[c] != 2'd0);
                r_we[c]    = b0_we[c];
                r_addr[c]  = b0_addr[c];
                r_data[c]  = b0_data[c];
            end else begin
                r_valid[c] = ch_read_valid[c] | ch_write_valid[c];
                r_we[c]    = ch_write_valid[c];
                r_addr[c]  = in_addr[c];
                r_data[c]  = ch_write_data_flat[c*BUS_BITS +: BUS_BITS];
            end
        end
    end

    wire [NUM_CHANNELS-1:0] cur_mask = (a_state == A_IDLE) ? {NUM_CHANNELS{1'b0}}
                                                           : (NUM_CHANNELS'(1) << cur);
    // Eligible: a request, not just served (program channels, and every
    // channel in async mode), no read of its own in flight (program
    // channels), not the async transaction in progress, and room for a read
    // in sync mode.
    wire [NUM_CHANNELS-1:0] share_hold;         // next read's word is in the shared lines: not for the bus (below)
    wire [NUM_CHANNELS-1:0] eligible = r_valid & ~taken_q & ~busy & ~cur_mask & ~share_hold &
                                       (r_we | {NUM_CHANNELS{~(sync_mode & q_full)}});

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

    wire                pick_we   = r_we[pick];
    wire                pick_sel  = (pick >= NUM_PROGRAM_CHANNELS);
    wire [BUS_BITS-1:0] pick_addr = r_addr[pick];
    wire [BUS_BITS-1:0] pick_data = r_data[pick];
    wire acked = (ack_q2 == bus_req);
    // Join the newest read in flight, unless it is answered this cycle or the
    // channel is already one of its readers (each of a channel's reads needs
    // its own answer: a tile's threads often read the same word).
    wire [Q_BITS-1:0] q_newest = q_wr - 1'b1;
    wire joins_newest = (q_count != 0) && !(answer && q_count == 1) &&
                        (last_sel == pick_sel) && (last_addr == pick_addr) &&
                        !q_mask[q_newest][pick] && !q_stale[q_newest];

    // Sync issue this cycle (the cycle of a write's data beat issues nothing new).
    wire s_issue = sync_mode & found & ~w_beat;
    wire w_issue = s_issue & pick_we;           // a write's address beat: later reads must see it
    wire [CH_BITS-1:0] next_rr = (pick == CH_BITS'(NUM_CHANNELS - 1)) ? {CH_BITS{1'b0}} : pick + 1'b1;

    // Shared-read lines.
    wire [NUM_CHANNELS-1:0] share_take;         // the channel answered from the lines this cycle
    wire [BUS_BITS-1:0]     share_word;         // its word
    generate
        if (SHARE_LINES > 0) begin : g_share
            localparam LB = (SHARE_LINES > 1) ? $clog2(SHARE_LINES) : 1;
            reg [BUS_BITS-4:0]       s_tag   [SHARE_LINES-1:0];
            reg [SHARE_LINES-1:0]    s_lvalid;
            reg [7:0]                s_wvalid[SHARE_LINES-1:0];
            reg [BUS_BITS-1:0]       s_data  [8*SHARE_LINES-1:0];
            reg [LB-1:0]             s_next;
            reg [CH_BITS-1:0]        s_rr;

            // Lookup: each data channel's next request, if a read. It is held
            // off the bus while its word is here, and answered once none of
            // the channel's reads is in flight.
            reg [SHARE_LINES-1:0] s_match [NUM_CHANNELS-1:0];
            reg [NUM_CHANNELS-1:0] hold, hit;
            integer sc, sl;
            always @(*) begin
                for (sc = 0; sc < NUM_CHANNELS; sc = sc + 1) begin
                    for (sl = 0; sl < SHARE_LINES; sl = sl + 1)
                        s_match[sc][sl] = s_lvalid[sl] && (s_tag[sl] == b0_addr[sc][BUS_BITS-1:3]) &&
                                          s_wvalid[sl][b0_addr[sc][2:0]];
                    hold[sc] = sync_mode && !PROG_MASK[sc] && (b_cnt[sc] != 2'd0) && !b0_we[sc] &&
                               (|s_match[sc]);
                    hit[sc]  = hold[sc] && (rcnt[sc] == '0);
                end
            end
            assign share_hold = hold;

            // One answer per cycle, rotating among the channels that hit.
            reg               s_found;
            reg [CH_BITS-1:0] s_pick;
            reg [BUS_BITS-1:0] s_word;
            integer sk, sw;
            always @(*) begin
                s_found = 1'b0;
                s_pick  = {CH_BITS{1'b0}};
                for (sk = 2 * NUM_CHANNELS - 1; sk >= 0; sk = sk - 1)
                    if (sk >= s_rr && sk < s_rr + NUM_CHANNELS && hit[sk % NUM_CHANNELS]) begin
                        s_found = 1'b1;
                        s_pick  = CH_BITS'(sk % NUM_CHANNELS);
                    end
                s_word = {BUS_BITS{1'b0}};
                for (sw = 0; sw < SHARE_LINES; sw = sw + 1)
                    if (s_match[s_pick][sw]) s_word = s_data[8*sw + b0_addr[s_pick][2:0]];
            end
            assign share_take = s_found ? (NUM_CHANNELS'(1) << s_pick) : {NUM_CHANNELS{1'b0}};
            assign share_word = s_word;

            // Fill from the answers to data reads issued since the last write.
            wire [BUS_BITS-1:0] f_addr = q_addr[q_rd];
            wire fill = answer && q_sel[q_rd] && !q_stale[q_rd] && !w_issue;
            reg [SHARE_LINES-1:0] f_match;
            integer sf, su;
            always @(*)
                for (sf = 0; sf < SHARE_LINES; sf = sf + 1)
                    f_match[sf] = s_lvalid[sf] && (s_tag[sf] == f_addr[BUS_BITS-1:3]);

            always @(posedge clk) begin
                if (reset) begin
                    s_lvalid <= {SHARE_LINES{1'b0}};
                    s_next   <= {LB{1'b0}};
                    s_rr     <= {CH_BITS{1'b0}};
                end else begin
                    if (s_found)
                        s_rr <= (s_pick == CH_BITS'(NUM_CHANNELS - 1)) ? {CH_BITS{1'b0}} : s_pick + 1'b1;
                    if (fill) begin
                        if (|f_match) begin
                            for (su = 0; su < SHARE_LINES; su = su + 1)
                                if (f_match[su]) begin
                                    s_wvalid[su][f_addr[2:0]]  <= 1'b1;
                                    s_data[8*su + f_addr[2:0]] <= in_q;
                                end
                        end else begin
                            s_tag[s_next]                 <= f_addr[BUS_BITS-1:3];
                            s_lvalid[s_next]              <= 1'b1;
                            s_wvalid[s_next]              <= 8'b1 << f_addr[2:0];
                            s_data[8*s_next + f_addr[2:0]] <= in_q;
                            s_next <= (s_next == LB'(SHARE_LINES - 1)) ? {LB{1'b0}} : s_next + 1'b1;
                        end
                    end
                    if (flush || w_issue || !sync_mode)
                        s_lvalid <= {SHARE_LINES{1'b0}};
                end
            end
        end else begin : g_no_share
            assign share_hold = {NUM_CHANNELS{1'b0}};
            assign share_take = {NUM_CHANNELS{1'b0}};
            assign share_word = {BUS_BITS{1'b0}};
        end
    endgenerate

    // Buffer moves this cycle (sync).
    reg [NUM_CHANNELS-1:0] b_push, b_pop;
    reg [1:0]              b_next [NUM_CHANNELS-1:0];
    always @(*) begin
        for (c = 0; c < NUM_CHANNELS; c = c + 1) begin
            b_push[c] = sync_mode && !PROG_MASK[c] && room[c] && (ch_read_valid[c] || ch_write_valid[c]);
            b_pop[c]  = (s_issue && (pick == CH_BITS'(c)) && !PROG_MASK[c]) || share_take[c];
            b_next[c] = b_cnt[c] + {1'b0, b_push[c]} - {1'b0, b_pop[c]};
        end
    end

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
            a_accept       <= {NUM_CHANNELS{1'b0}};
            a_wready       <= {NUM_CHANNELS{1'b0}};
            room           <= ~PROG_MASK;
            taken_q        <= {NUM_CHANNELS{1'b0}};
            busy           <= {NUM_CHANNELS{1'b0}};
            q_rd           <= {Q_BITS{1'b0}};
            q_wr           <= {Q_BITS{1'b0}};
            q_count        <= {(Q_BITS+1){1'b0}};
            last_addr      <= {BUS_BITS{1'b0}};
            last_sel       <= 1'b0;
            q_stale        <= {OUTSTANDING{1'b0}};
            shared_q       <= {NUM_CHANNELS{1'b0}};
            share_data     <= {BUS_BITS{1'b0}};
            for (i = 0; i < NUM_CHANNELS; i = i + 1) rcnt[i] <= '0;
            w_beat         <= 1'b0;
            w_data         <= {BUS_BITS{1'b0}};
            ch_read_ready  <= {NUM_CHANNELS{1'b0}};
            bus_out        <= {BUS_BITS{1'b0}};
            bus_sel        <= 1'b0;
            bus_we         <= 1'b0;
            bus_beat       <= 1'b0;
            bus_req        <= 1'b0;
            for (i = 0; i < NUM_CHANNELS; i = i + 1) b_cnt[i] <= 2'd0;
        end else begin
            ack_q1 <= bus_ack;
            ack_q2 <= ack_q1;
            in_q   <= bus_in;
            a_accept      <= {NUM_CHANNELS{1'b0}};
            a_wready      <= {NUM_CHANNELS{1'b0}};
            ch_read_ready <= {NUM_CHANNELS{1'b0}};
            taken_q       <= {NUM_CHANNELS{1'b0}};

            if (!sync_mode) begin
                // ---------------- async: one handshake at a time ----------------
                shared_q <= {NUM_CHANNELS{1'b0}};
                case (a_state)
                    A_IDLE: begin
                        if (found) begin
                            cur      <= pick;
                            rr       <= next_rr;
                            bus_sel  <= pick_sel;
                            bus_we   <= pick_we;
                            bus_beat <= 1'b0;
                            bus_out  <= pick_addr;
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
                            bus_out  <= r_data[cur];
                            bus_beat <= 1'b1;
                            a_state  <= A_DATA;
                        end else if (acked) begin
                            if (bus_we) begin
                                a_wready[cur] <= 1'b1;
                            end else begin
                                rdata              <= bus_in;
                                ch_read_ready[cur] <= 1'b1;
                                a_accept[cur]      <= 1'b1;
                            end
                            taken_q[cur] <= 1'b1;
                            // the next transaction starts now
                            if (found) begin
                                cur      <= pick;
                                rr       <= next_rr;
                                bus_sel  <= pick_sel;
                                bus_we   <= pick_we;
                                bus_beat <= 1'b0;
                                bus_out  <= pick_addr;
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

                // Answers, oldest read first, and one from the shared lines.
                ch_read_ready <= (answer ? q_mask[q_rd] : {NUM_CHANNELS{1'b0}}) | share_take;
                shared_q      <= share_take;
                share_data    <= share_word;
                if (answer) begin
                    rdata         <= in_q;
                    busy          <= busy & ~q_mask[q_rd];
                    taken_q       <= q_mask[q_rd] & PROG_MASK;    // program channels drop valid next
                    q_rd          <= q_rd + 1'b1;
                end

                if (w_beat) begin
                    bus_out  <= w_data;
                    bus_we   <= 1'b1;
                    bus_beat <= 1'b1;
                    bus_req  <= 1'b1;
                    w_beat   <= 1'b0;
                end else if (found) begin
                    rr <= STICKY ? pick : next_rr;
                    if (pick_we) begin
                        q_stale  <= {OUTSTANDING{1'b1}};
                        bus_out  <= pick_addr;
                        bus_sel  <= 1'b1;
                        bus_we   <= 1'b1;
                        bus_beat <= 1'b0;
                        bus_req  <= 1'b1;
                        w_beat   <= 1'b1;
                        w_data   <= pick_data;
                    end else begin
                        if (joins_newest) begin
                            q_mask[q_newest][pick] <= 1'b1;
                        end else begin
                            bus_out       <= pick_addr;
                            bus_sel       <= pick_sel;
                            bus_we        <= 1'b0;
                            bus_beat      <= 1'b0;
                            bus_req       <= 1'b1;
                            q_mask[q_wr]  <= NUM_CHANNELS'(1) << pick;
                            q_addr[q_wr]  <= pick_addr;
                            q_sel[q_wr]   <= pick_sel;
                            q_stale[q_wr] <= 1'b0;
                            q_wr          <= q_wr + 1'b1;
                            last_addr     <= pick_addr;
                            last_sel      <= pick_sel;
                        end
                        if (PROG_MASK[pick]) begin
                            busy[pick]    <= 1'b1;
                            taken_q[pick] <= 1'b1;
                        end
                    end
                end

                q_count <= q_count + {{Q_BITS{1'b0}}, (s_issue && !pick_we && !joins_newest)}
                                   - {{Q_BITS{1'b0}}, answer};
                for (i = 0; i < NUM_CHANNELS; i = i + 1)
                    rcnt[i] <= rcnt[i] + {{Q_BITS{1'b0}}, (s_issue && !pick_we && pick == CH_BITS'(i))}
                                       - {{Q_BITS{1'b0}}, (answer && q_mask[q_rd][i])};

                // Data channel buffers: take a request where room was
                // offered, pop the head when it issues.
                for (i = 0; i < NUM_CHANNELS; i = i + 1) begin
                    if (!PROG_MASK[i]) begin
                        if (b_pop[i]) begin
                            b0_we[i]   <= b1_we[i];
                            b0_addr[i] <= b1_addr[i];
                            b0_data[i] <= b1_data[i];
                        end
                        if (b_push[i]) begin
                            // into the first free entry once the pop is done
                            if (b_cnt[i] - {1'b0, b_pop[i]} == 2'd0) begin
                                b0_we[i]   <= ch_write_valid[i];
                                b0_addr[i] <= in_addr[i];
                                b0_data[i] <= ch_write_data_flat[i*BUS_BITS +: BUS_BITS];
                            end else begin
                                b1_we[i]   <= ch_write_valid[i];
                                b1_addr[i] <= in_addr[i];
                                b1_data[i] <= ch_write_data_flat[i*BUS_BITS +: BUS_BITS];
                            end
                        end
                        b_cnt[i] <= b_next[i];
                        room[i]  <= (b_next[i] <= 2'd1);
                    end else begin
                        // Program channels bypass the buffers; hold them at
                        // zero so every reference to them has a driver.
                        b0_we[i]   <= 1'b0;
                        b1_we[i]   <= 1'b0;
                        b0_addr[i] <= {BUS_BITS{1'b0}};
                        b1_addr[i] <= {BUS_BITS{1'b0}};
                        b0_data[i] <= {BUS_BITS{1'b0}};
                        b1_data[i] <= {BUS_BITS{1'b0}};
                    end
                end
            end
        end
    end
endmodule

`default_nettype wire
