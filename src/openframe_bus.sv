`default_nettype none
`timescale 1ns/1ns

// OPENFRAME PIN BUS — external program/data memory over GPIO
//
// Serves NUM_CHANNELS internal memory channels (program channels first, then
// data channels) one transaction at a time over a 16-bit out bus and a 16-bit
// in bus. The chip is the bus master; the host holds program and data memory.
//
// Handshake is two-phase: the chip toggles REQ, the host answers by making ACK
// equal to REQ. ACK passes through a two-flop synchronizer, so the host may run
// on its own clock. Every output is registered and settles one cycle before REQ
// toggles.
//
//   Read  (1 beat):  OUT=address, SEL, WE=0, BEAT=0, toggle REQ
//                    host puts the word on IN, then sets ACK=REQ
//   Write (2 beats): OUT=address, SEL, WE=1, BEAT=0, toggle REQ; wait ACK=REQ
//                    OUT=data,             BEAT=1, toggle REQ; wait ACK=REQ
//
// SEL is 0 for program memory, 1 for data memory. After reset REQ=0 and the
// host must hold ACK=0. IN must be stable before the host changes ACK and stay
// stable until REQ toggles again.
//
// Each channel first selects its own outgoing word (write data while the
// address beat is being acknowledged, else its write or read address), so the
// shared mux into bus_out sees one 16-bit word per channel. On the chip the
// channels come from four tiles; the per-channel select sits by each tile and
// only NUM_CHANNELS words reach the shared logic.
module openframe_bus #(
    parameter NUM_CHANNELS = 8,
    parameter NUM_PROGRAM_CHANNELS = 4,
    parameter BUS_BITS = 16
) (
    input  wire clk,
    input  wire reset,

    // Channel side: valid is held until the one-cycle ready pulse
    input  wire [NUM_CHANNELS-1:0]          ch_read_valid,
    input  wire [BUS_BITS*NUM_CHANNELS-1:0] ch_read_address_flat,
    output reg  [NUM_CHANNELS-1:0]          ch_read_ready,
    output wire [BUS_BITS-1:0]              ch_read_data,      // shared, valid with the ready pulse
    input  wire [NUM_CHANNELS-1:0]          ch_write_valid,
    input  wire [BUS_BITS*NUM_CHANNELS-1:0] ch_write_address_flat,
    input  wire [BUS_BITS*NUM_CHANNELS-1:0] ch_write_data_flat,
    output reg  [NUM_CHANNELS-1:0]          ch_write_ready,

    // Pins
    output reg  [BUS_BITS-1:0] bus_out,
    output reg                 bus_sel,
    output reg                 bus_we,
    output reg                 bus_beat,
    output reg                 bus_req,
    input  wire [BUS_BITS-1:0] bus_in,
    input  wire                bus_ack
);
    localparam CH_BITS = (NUM_CHANNELS > 1) ? $clog2(NUM_CHANNELS) : 1;

    localparam [2:0] S_IDLE      = 3'd0,
                     S_ADDR      = 3'd1,
                     S_ADDR_WAIT = 3'd2,
                     S_DATA      = 3'd3,
                     S_DATA_WAIT = 3'd4,
                     S_DONE      = 3'd5;

    reg [2:0]          state;
    reg [CH_BITS-1:0]  cur;
    reg [CH_BITS-1:0]  rr_next;       // round-robin start point
    reg                ack_q1, ack_q2;
    reg [BUS_BITS-1:0] rdata;

    assign ch_read_data = rdata;

    wire [NUM_CHANNELS-1:0] pending = ch_read_valid | ch_write_valid;
    wire                    acked   = (ack_q2 == bus_req);

    // Per-channel outgoing word: the data beat is loaded in S_ADDR_WAIT, the
    // address beat in S_IDLE.
    wire data_beat = (state == S_ADDR_WAIT);
    wire [BUS_BITS-1:0] ch_word [NUM_CHANNELS-1:0];
    genvar gc;
    generate
        for (gc = 0; gc < NUM_CHANNELS; gc = gc + 1) begin : words
            assign ch_word[gc] = data_beat         ? ch_write_data_flat[gc*BUS_BITS +: BUS_BITS] :
                                 ch_write_valid[gc] ? ch_write_address_flat[gc*BUS_BITS +: BUS_BITS] :
                                                      ch_read_address_flat[gc*BUS_BITS +: BUS_BITS];
        end
    endgenerate

    // Round-robin pick: first pending channel at or after rr_next.
    reg                found;
    reg [CH_BITS-1:0]  pick;
    integer k;
    always @(*) begin
        found = 1'b0;
        pick  = {CH_BITS{1'b0}};
        for (k = 2 * NUM_CHANNELS - 1; k >= 0; k = k - 1) begin
            if (k >= rr_next && k < rr_next + NUM_CHANNELS && pending[k % NUM_CHANNELS]) begin
                found = 1'b1;
                pick  = CH_BITS'(k % NUM_CHANNELS);
            end
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            state          <= S_IDLE;
            cur            <= {CH_BITS{1'b0}};
            rr_next        <= {CH_BITS{1'b0}};
            ack_q1         <= 1'b0;
            ack_q2         <= 1'b0;
            rdata          <= {BUS_BITS{1'b0}};
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
            ch_read_ready  <= {NUM_CHANNELS{1'b0}};
            ch_write_ready <= {NUM_CHANNELS{1'b0}};

            case (state)
                S_IDLE: begin
                    if (found) begin
                        cur      <= pick;
                        bus_sel  <= (pick >= NUM_PROGRAM_CHANNELS);
                        bus_we   <= ch_write_valid[pick];
                        bus_beat <= 1'b0;
                        bus_out  <= ch_word[pick];
                        state    <= S_ADDR;
                    end
                end
                S_ADDR: begin
                    bus_req <= ~bus_req;
                    state   <= S_ADDR_WAIT;
                end
                S_ADDR_WAIT: begin
                    if (acked) begin
                        if (bus_we) begin
                            bus_out  <= ch_word[cur];
                            bus_beat <= 1'b1;
                            state    <= S_DATA;
                        end else begin
                            rdata              <= bus_in;
                            ch_read_ready[cur] <= 1'b1;
                            state              <= S_DONE;
                        end
                    end
                end
                S_DATA: begin
                    bus_req <= ~bus_req;
                    state   <= S_DATA_WAIT;
                end
                S_DATA_WAIT: begin
                    if (acked) begin
                        ch_write_ready[cur] <= 1'b1;
                        state               <= S_DONE;
                    end
                end
                S_DONE: begin
                    // The channel drops valid on the same edge it sees ready,
                    // so the next pick never sees this request again.
                    rr_next <= (cur == CH_BITS'(NUM_CHANNELS - 1)) ? {CH_BITS{1'b0}} : cur + 1'b1;
                    state   <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
