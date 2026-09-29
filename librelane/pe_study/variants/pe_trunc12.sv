`default_nettype none
`timescale 1ns / 1ps

// Lean PE with a column-truncated multiplier (K=12); NOT bit-exact.
// - Inputs are canonical (the array cleans negative zero at its edges).
// - The weight register doubles as the southward weight chain; it shifts only
//   on load_weight.
// - a_out, R3 and the valid pipe run freely; the accumulator only moves on
//   valid_s1 or clear.
// - acc_raw is the two's-complement accumulator; the readout converts it.
module systolic_pe_trunc12 #(
    parameter DATA_BITS = 16
) (
    input  wire                  clk,
    input  wire                  reset,
    input  wire                  clear_acc,
    input  wire                  load_weight,
    input  wire                  compute_enable,
    input  wire [DATA_BITS-1:0]  a_in,
    input  wire [DATA_BITS-1:0]  b_in,
    output reg  [DATA_BITS-1:0]  a_out,
    output reg  [DATA_BITS-1:0]  b_out,      // = stationary weight
    output reg  signed [15:0]    acc_raw
);
    reg        valid_s0, valid_s1;
    reg [14:0] r3_mant;
    reg        r3_sign;

    // Column-truncated product: partial-product bits below column 12 are
    // dropped and replaced by their expected sum (11264). One multi-operand add
    // so synthesis builds a carry-save tree.
    wire [29:0] prod =
        30'd11264 +
        (b_out[0] ? ({15'd0, a_out[14:0] & 15'h7000} << 0) : 30'd0) +
        (b_out[1] ? ({15'd0, a_out[14:0] & 15'h7800} << 1) : 30'd0) +
        (b_out[2] ? ({15'd0, a_out[14:0] & 15'h7C00} << 2) : 30'd0) +
        (b_out[3] ? ({15'd0, a_out[14:0] & 15'h7E00} << 3) : 30'd0) +
        (b_out[4] ? ({15'd0, a_out[14:0] & 15'h7F00} << 4) : 30'd0) +
        (b_out[5] ? ({15'd0, a_out[14:0] & 15'h7F80} << 5) : 30'd0) +
        (b_out[6] ? ({15'd0, a_out[14:0] & 15'h7FC0} << 6) : 30'd0) +
        (b_out[7] ? ({15'd0, a_out[14:0] & 15'h7FE0} << 7) : 30'd0) +
        (b_out[8] ? ({15'd0, a_out[14:0] & 15'h7FF0} << 8) : 30'd0) +
        (b_out[9] ? ({15'd0, a_out[14:0] & 15'h7FF8} << 9) : 30'd0) +
        (b_out[10] ? ({15'd0, a_out[14:0] & 15'h7FFC} << 10) : 30'd0) +
        (b_out[11] ? ({15'd0, a_out[14:0] & 15'h7FFE} << 11) : 30'd0) +
        (b_out[12] ? ({15'd0, a_out[14:0] & 15'h7FFF} << 12) : 30'd0) +
        (b_out[13] ? ({15'd0, a_out[14:0] & 15'h7FFF} << 13) : 30'd0) +
        (b_out[14] ? ({15'd0, a_out[14:0] & 15'h7FFF} << 14) : 30'd0);

    wire signed [16:0] acc_ext = {acc_raw[15], acc_raw};
    wire signed [16:0] prd_ext = {2'b0, r3_mant};
    wire signed [16:0] sum = r3_sign ? (acc_ext - prd_ext) : (acc_ext + prd_ext);
    wire ovf  = (sum[16] != sum[15]);
    wire negz = (sum[15:0] == 16'h8000);
    wire signed [15:0] sat = (ovf || negz) ? (sum[16] ? 16'sh8001 : 16'sh7FFF) : sum[15:0];

    always @(posedge clk) begin
        if (reset) begin
            a_out    <= {DATA_BITS{1'b0}};
            b_out    <= {DATA_BITS{1'b0}};
            r3_mant  <= 15'b0;
            r3_sign  <= 1'b0;
            acc_raw  <= 16'sb0;
            valid_s0 <= 1'b0;
            valid_s1 <= 1'b0;
        end else begin
            a_out   <= a_in;
            if (load_weight) b_out <= b_in;
            r3_mant <= prod[29:15];
            r3_sign <= a_out[15] ^ b_out[15];
            if (clear_acc) begin
                acc_raw  <= 16'sb0;
                valid_s0 <= 1'b0;
                valid_s1 <= 1'b0;
            end else begin
                valid_s0 <= compute_enable;
                valid_s1 <= valid_s0;
                if (valid_s1) acc_raw <= sat;
            end
        end
    end
endmodule
