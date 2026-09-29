`default_nettype none
`timescale 1ns / 1ps

// Lean PE with a two-stage multiplier (4-stage MAC): bit-exact results,
// one cycle more latency than pe_lean.
// - Inputs are canonical (the array cleans negative zero at its edges).
// - The weight register doubles as the southward weight chain; it shifts only
//   on load_weight.
// - a_out, R3 and the valid pipe run freely; the accumulator only moves on
//   valid_s1 or clear.
// - acc_raw is the two's-complement accumulator; the readout converts it.
module systolic_pe_pipe #(
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
    reg        valid_s0, valid_s1, valid_s2;
    reg [21:0] p_hi;   // a * w[14:8]
    reg [22:0] p_lo;   // a * w[7:0]
    reg        sign_s1;
    reg [14:0] r3_mant;
    reg        r3_sign;

    wire [29:0] prod = {p_hi, 8'b0} + {7'b0, p_lo};

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
            valid_s2 <= 1'b0;
            p_hi     <= 22'b0;
            p_lo     <= 23'b0;
            sign_s1  <= 1'b0;
        end else begin
            a_out   <= a_in;
            if (load_weight) b_out <= b_in;
            p_hi    <= a_out[14:0] * b_out[14:8];
            p_lo    <= a_out[14:0] * b_out[7:0];
            sign_s1 <= a_out[15] ^ b_out[15];
            r3_mant <= prod[29:15];
            r3_sign <= sign_s1;
            if (clear_acc) begin
                acc_raw  <= 16'sb0;
                valid_s0 <= 1'b0;
                valid_s1 <= 1'b0;
                valid_s2 <= 1'b0;
            end else begin
                valid_s0 <= compute_enable;
                valid_s1 <= valid_s0;
                valid_s2 <= valid_s1;
                if (valid_s2) acc_raw <= sat;
            end
        end
    end
endmodule
