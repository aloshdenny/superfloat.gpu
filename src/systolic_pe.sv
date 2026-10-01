// =============================================================================
// SYSTOLIC PE — SF16 × SF16 weight-stationary MAC (3-stage pipeline)
//
// SF16 format: x = (-1)^s · m / 2^15,  m ∈ [0, 2^15-1]
//   bit[15]    = sign
//   bits[14:0] = 15-bit unsigned mantissa
//
// Pipeline:
//   Stage 0 : a_out  <= a_in                       (activation, forwarded east)
//             b_out  <= b_in on load_weight        (stationary weight, forwarded south)
//   Stage 1 : R3     <= (a_out.m × b_out.m)[29:15], sign = a_out.s ^ b_out.s
//   Stage 2 : acc    <= sat16(acc ± R3)            (on valid, two's complement)
//             The 17-bit add is a carry-select adder: the low 9 bits and both
//             possible high 8-bit sums are computed at once, the low carry
//             picks one, and the saturation checks are made per half.
// Latency: an operand presented with compute_enable reaches the accumulator
// three edges later. Throughput: one MAC per cycle.
//
// Contract with systolic_array (the only instantiator):
//   - a_in / b_in are canonical: the array maps negative zero (0x8000) to +0 at
//     its edges, so interior PEs never see it.
//   - The weight register is also the southward weight chain. It shifts only on
//     load_weight, so N load pulses place N rows (last row first).
//   - a_out, R3 and the valid pipe run every cycle; only the accumulator is
//     gated (valid or clear). The core holds each SYS operand, so a row settles
//     to the last compute's operand between instructions.
//   - acc_raw is the 16-bit two's-complement accumulator, saturating to
//     [-32767, +32767]. The core converts the one cell it reads to SF16.
//
// Compared with the previous PE (separate b_out chain, per-PE enable, per-PE
// canonicalisation and sign-magnitude output), this is bit-exact inside the
// array and, hardened on Sky130 HD at 20 ns: 16,610.9 um2 vs 18,147.4 um2,
// 66 vs 82 flops, 1.16 vs 1.24 mW at a full-rate MAC stream (nom_tt_025C_1v80,
// activity from gate-level simulation).
// =============================================================================
`default_nettype none
`timescale 1ns / 1ps

module systolic_pe #(
    parameter DATA_BITS = 16
) (
    input  wire                  clk,
    input  wire                  reset,

    // ---- control ----
    input  wire                  clear_acc,      // synchronous accumulator clear
    input  wire                  load_weight,    // shift the weight chain one row
    input  wire                  compute_enable, // accumulate this cycle's operand

    // ---- data (west→east, north→south) ----
    input  wire [DATA_BITS-1:0]  a_in,
    input  wire [DATA_BITS-1:0]  b_in,
    output reg  [DATA_BITS-1:0]  a_out,
    output reg  [DATA_BITS-1:0]  b_out,          // = stationary weight

    // ---- result ----
    output reg  signed [15:0]    acc_raw         // two's complement accumulator
);
    reg        valid_s0, valid_s1;
    reg [14:0] r3_mant;
    reg        r3_sign;

    // Stage 1: 15×15 unsigned product, keep the Q1.15 bits.
    wire [29:0] prod = a_out[14:0] * b_out[14:0];

    // Stage 2: saturating add/subtract of the product magnitude,
    // sum = acc + (r3_sign ? -prd : prd) = acc + (prd ^ {17{r3_sign}}) + r3_sign.
    wire [16:0] acc_ext = {acc_raw[15], acc_raw};
    wire [16:0] prd_op  = {2'b0, r3_mant} ^ {17{r3_sign}};
    wire [9:0]  lo      = {1'b0, acc_ext[8:0]} + {1'b0, prd_op[8:0]} + {9'b0, r3_sign};
    wire [7:0]  hi0     = acc_ext[16:9] + prd_op[16:9];
    wire [7:0]  hi1     = acc_ext[16:9] + prd_op[16:9] + 8'd1;
    wire        c9      = lo[9];
    wire [16:0] sum     = {c9 ? hi1 : hi0, lo[8:0]};
    // sum[16] != sum[15]: overflow; sum[15:0] == 0x8000: -32768, which SF16
    // cannot represent. Both from each high candidate, then picked by c9.
    wire ovf  = c9 ? (hi1[7] ^ hi1[6]) : (hi0[7] ^ hi0[6]);
    wire negz = (lo[8:0] == 9'd0) && (c9 ? (hi1[6:0] == 7'h40) : (hi0[6:0] == 7'h40));
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
