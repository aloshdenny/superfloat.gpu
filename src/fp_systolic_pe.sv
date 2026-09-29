// =============================================================================
// FP SYSTOLIC PE: FP16 / BF16 weight-stationary MAC (5-stage pipeline)
//
// Same contract as systolic_pe (see there), with an IEEE-style 16-bit format:
//   FP16: EXP_BITS 5, MANT_BITS 10      BF16: EXP_BITS 8, MANT_BITS 7
//
// Each compute performs acc <= round(a * w + acc), one rounding, as defined
// in fp_arith.sv (round to nearest even, flush to zero, canonical NaN).
//
// Pipeline:
//   Stage 0 : a_out <= a_in                         (activation, forwarded east)
//             b_out <= b_in on load_weight          (stationary weight, forwarded south)
//   Stage 1 : product registers <= fp_mul(a_out, b_out)
//   Stage 2 : aligned registers <= fp_align(product, acc)
//   Stage 3 : sum registers     <= fp_addsub(aligned)
//   Stage 4 : acc               <= fp_round(sum)    (on valid)
// Stages 0-3 run every cycle; only the accumulator is gated.
//
// The accumulator loop (stages 2 to 4) spans three cycles, so two computes
// must be at least three cycles apart. The core issues at most one SYS
// compute per instruction, and an instruction takes at least six cycles.
//
// Unlike SF16 there is no canonicalisation: negative zero is a valid operand
// and affects the sign of a zero result. acc is the result in the same format.
// =============================================================================
`default_nettype none
`timescale 1ns / 1ps

module fp_systolic_pe #(
    parameter EXP_BITS  = 5,
    parameter MANT_BITS = 10,
    parameter DATA_BITS = 1 + EXP_BITS + MANT_BITS
) (
    input  wire                  clk,
    input  wire                  reset,

    // ---- control ----
    input  wire                  clear_acc,      // synchronous accumulator clear (+0)
    input  wire                  load_weight,    // shift the weight chain one row
    input  wire                  compute_enable, // accumulate this cycle's operand

    // ---- data (west→east, north→south) ----
    input  wire [DATA_BITS-1:0]  a_in,
    input  wire [DATA_BITS-1:0]  b_in,
    output reg  [DATA_BITS-1:0]  a_out,
    output reg  [DATA_BITS-1:0]  b_out,          // = stationary weight

    // ---- result ----
    output reg  [DATA_BITS-1:0]  acc
);
    localparam M  = MANT_BITS + 1;
    localparam EW = EXP_BITS + 4;
    localparam AW = 2 * M + 3;

    reg valid_s0, valid_s1, valid_s2, valid_s3;

    // Stage 1: significand product
    wire [2*M-1:0]       mul_prod;
    wire signed [EW-1:0] mul_top;
    wire                 mul_sign, mul_zero, mul_inf, mul_nan;
    fp_mul #(.EXP_BITS(EXP_BITS), .MANT_BITS(MANT_BITS)) u_mul (
        .a(a_out), .b(b_out),
        .prod(mul_prod), .top_exp(mul_top),
        .sign(mul_sign), .zero(mul_zero), .inf(mul_inf), .nan(mul_nan)
    );

    reg [2*M-1:0]       p_prod;
    reg signed [EW-1:0] p_top;
    reg                 p_sign, p_zero, p_inf, p_nan;

    // Stage 2: align the product and the accumulator
    wire [AW-1:0]        al_hi, al_lo;
    wire signed [EW-1:0] al_top;
    wire                 al_hi_sign, al_lo_sign, al_sub, al_zero, al_inf, al_inf_sign, al_nan;
    fp_align #(.EXP_BITS(EXP_BITS), .MANT_BITS(MANT_BITS)) u_align (
        .prod(p_prod), .p_top(p_top),
        .p_sign(p_sign), .p_zero(p_zero), .p_inf(p_inf), .p_nan(p_nan),
        .c(acc),
        .hi(al_hi), .lo(al_lo), .top_exp(al_top), .hi_sign(al_hi_sign), .lo_sign(al_lo_sign),
        .sub(al_sub), .zero(al_zero), .inf(al_inf), .inf_sign(al_inf_sign), .nan(al_nan)
    );

    reg [AW-1:0]        q_hi, q_lo;
    reg signed [EW-1:0] q_top;
    reg                 q_hi_sign, q_lo_sign, q_sub, q_zero, q_inf, q_inf_sign, q_nan;

    // Stage 3: add or subtract
    wire [AW:0]          add_mag;
    wire signed [EW-1:0] add_top;
    wire                 add_sign, add_zero, add_inf, add_nan;
    fp_addsub #(.EXP_BITS(EXP_BITS), .MANT_BITS(MANT_BITS)) u_addsub (
        .hi(q_hi), .lo(q_lo), .in_top(q_top), .hi_sign(q_hi_sign), .lo_sign(q_lo_sign),
        .sub(q_sub), .in_zero(q_zero), .in_inf(q_inf), .inf_sign(q_inf_sign), .in_nan(q_nan),
        .mag(add_mag), .top_exp(add_top),
        .sign(add_sign), .zero(add_zero), .inf(add_inf), .nan(add_nan)
    );

    reg [AW:0]          s_mag;
    reg signed [EW-1:0] s_top;
    reg                 s_sign, s_zero, s_inf, s_nan;

    // Stage 4: normalise and round
    wire [DATA_BITS-1:0] rounded;
    fp_round #(.EXP_BITS(EXP_BITS), .MANT_BITS(MANT_BITS)) u_round (
        .mag(s_mag), .top_exp(s_top),
        .sign(s_sign), .zero(s_zero), .inf(s_inf), .nan(s_nan),
        .result(rounded)
    );

    always @(posedge clk) begin
        if (reset) begin
            a_out    <= {DATA_BITS{1'b0}};
            b_out    <= {DATA_BITS{1'b0}};
            p_prod   <= {(2*M){1'b0}};
            p_top    <= {EW{1'b0}};
            {p_sign, p_zero, p_inf, p_nan} <= 4'b0;
            q_hi     <= {AW{1'b0}};
            q_lo     <= {AW{1'b0}};
            q_top    <= {EW{1'b0}};
            {q_hi_sign, q_lo_sign, q_sub, q_zero, q_inf, q_inf_sign, q_nan} <= 7'b0;
            s_mag    <= {(AW+1){1'b0}};
            s_top    <= {EW{1'b0}};
            {s_sign, s_zero, s_inf, s_nan} <= 4'b0;
            acc      <= {DATA_BITS{1'b0}};
            valid_s0 <= 1'b0;
            valid_s1 <= 1'b0;
            valid_s2 <= 1'b0;
            valid_s3 <= 1'b0;
        end else begin
            a_out <= a_in;
            if (load_weight) b_out <= b_in;
            p_prod <= mul_prod;
            p_top  <= mul_top;
            {p_sign, p_zero, p_inf, p_nan} <= {mul_sign, mul_zero, mul_inf, mul_nan};
            q_hi   <= al_hi;
            q_lo   <= al_lo;
            q_top  <= al_top;
            {q_hi_sign, q_lo_sign, q_sub, q_zero, q_inf, q_inf_sign, q_nan} <=
                {al_hi_sign, al_lo_sign, al_sub, al_zero, al_inf, al_inf_sign, al_nan};
            s_mag  <= add_mag;
            s_top  <= add_top;
            {s_sign, s_zero, s_inf, s_nan} <= {add_sign, add_zero, add_inf, add_nan};
            if (clear_acc) begin
                acc      <= {DATA_BITS{1'b0}};
                valid_s0 <= 1'b0;
                valid_s1 <= 1'b0;
                valid_s2 <= 1'b0;
                valid_s3 <= 1'b0;
            end else begin
                valid_s0 <= compute_enable;
                valid_s1 <= valid_s0;
                valid_s2 <= valid_s1;
                valid_s3 <= valid_s2;
                if (valid_s3) acc <= rounded;
            end
        end
    end
endmodule
