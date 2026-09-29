`default_nettype none
`timescale 1ns/1ns

// IEEE-style 16-bit floating-point datapath (FP16: 5/10, BF16: 8/7)
//
// Three combinational stages that together compute round(a*b + c), the fused
// multiply-add used by the systolic PEs, the per-thread FMA units and the
// activation units. Callers place a register after each stage.
//
//   fp_mul   : exact significand product and its exponent
//   fp_add   : align the product and the addend (sticky right shift) and add
//   fp_round : normalise, round to nearest even, flush to zero, overflow
//
// Semantics (bit-exact reference: test/helpers/fp16fmt.py):
//   - one rounding of the exact a*b + c, round to nearest, ties to even
//   - subnormal inputs read as signed zero; a result smaller than the smallest
//     normal before rounding becomes a signed zero
//   - overflow after rounding gives signed infinity
//   - NaN in, inf*0 or inf-inf gives the canonical quiet NaN (sign 0)
//   - IEEE 754 zero signs: an exact zero sum of non-zero terms is +0,
//     0 + 0 is -0 only if both are -0
//
// The adder window holds the full 2M-bit product plus three bits below it.
// When an operand is shifted far enough to lose bits, cancellation is limited
// to one bit, so a single sticky bit keeps the rounding exact.

module fp_mul #(
    parameter EXP_BITS  = 5,
    parameter MANT_BITS = 10,
    parameter W  = 1 + EXP_BITS + MANT_BITS,
    parameter M  = MANT_BITS + 1,
    parameter EW = EXP_BITS + 4
) (
    input  wire [W-1:0]         a,
    input  wire [W-1:0]         b,
    output wire [2*M-1:0]       prod,      // exact product of the significands
    output wire signed [EW-1:0] top_exp,   // unbiased exponent of prod[2M-1]
    output wire                 sign,
    output wire                 zero,
    output wire                 inf,
    output wire                 nan
);
    localparam integer BIAS    = (1 << (EXP_BITS - 1)) - 1;
    localparam integer EXP_ONE = (1 << EXP_BITS) - 1;

    wire [EXP_BITS-1:0]  ae = a[W-2 -: EXP_BITS];
    wire [EXP_BITS-1:0]  be = b[W-2 -: EXP_BITS];
    wire [MANT_BITS-1:0] af = a[MANT_BITS-1:0];
    wire [MANT_BITS-1:0] bf = b[MANT_BITS-1:0];

    wire a_zero = (ae == 0);
    wire b_zero = (be == 0);
    wire a_inf  = (ae == EXP_ONE) && (af == 0);
    wire b_inf  = (be == EXP_ONE) && (bf == 0);
    wire a_nan  = (ae == EXP_ONE) && (af != 0);
    wire b_nan  = (be == EXP_ONE) && (bf != 0);

    assign sign = a[W-1] ^ b[W-1];
    assign nan  = a_nan || b_nan || (a_inf && b_zero) || (b_inf && a_zero);
    assign inf  = !nan && (a_inf || b_inf);
    assign zero = !nan && !inf && (a_zero || b_zero);

    wire [M-1:0] am = {1'b1, af};
    wire [M-1:0] bm = {1'b1, bf};
    assign prod = am * bm;
    // a = am * 2^(ae-BIAS-m), b likewise; prod[2M-2] weighs 2^(ae+be-2*BIAS).
    assign top_exp = $signed({{(EW-EXP_BITS){1'b0}}, ae}) + $signed({{(EW-EXP_BITS){1'b0}}, be})
                   - $signed(EW'(2 * BIAS - 1));
endmodule


module fp_add #(
    parameter EXP_BITS  = 5,
    parameter MANT_BITS = 10,
    parameter W  = 1 + EXP_BITS + MANT_BITS,
    parameter M  = MANT_BITS + 1,
    parameter EW = EXP_BITS + 4,
    parameter AW = 2 * M + 3
) (
    input  wire [2*M-1:0]       prod,
    input  wire signed [EW-1:0] p_top,
    input  wire                 p_sign,
    input  wire                 p_zero,
    input  wire                 p_inf,
    input  wire                 p_nan,
    input  wire [W-1:0]         c,
    output reg  [AW:0]          mag,       // bit AW is the carry
    output reg  signed [EW-1:0] top_exp,   // unbiased exponent of mag[AW-1]
    output reg                  sign,
    output wire                 zero,      // exact zero result (sign valid)
    output wire                 inf,
    output wire                 nan
);
    localparam integer BIAS    = (1 << (EXP_BITS - 1)) - 1;
    localparam integer EXP_ONE = (1 << EXP_BITS) - 1;

    wire [EXP_BITS-1:0]  ce = c[W-2 -: EXP_BITS];
    wire [MANT_BITS-1:0] cf = c[MANT_BITS-1:0];
    wire c_sign = c[W-1];
    wire c_zero = (ce == 0);
    wire c_inf  = (ce == EXP_ONE) && (cf == 0);
    wire c_nan  = (ce == EXP_ONE) && (cf != 0);

    assign nan = p_nan || c_nan || (p_inf && c_inf && (p_sign != c_sign));
    assign inf = !nan && (p_inf || c_inf);

    wire [AW-1:0] p_w = {prod, 3'b000};
    wire [AW-1:0] c_w = {1'b1, cf, {M{1'b0}}, 3'b000};
    wire signed [EW-1:0] c_top = $signed({{(EW-EXP_BITS){1'b0}}, ce}) - $signed(EW'(BIAS));
    wire signed [EW:0]   diff  = $signed({p_top[EW-1], p_top}) - $signed({c_top[EW-1], c_top});

    function automatic [AW-1:0] shr_sticky(input [AW-1:0] v, input integer n);
        reg [AW-1:0] kept;
        begin
            if (n <= 0) begin
                shr_sticky = v;
            end else if (n >= AW) begin
                shr_sticky = {{(AW-1){1'b0}}, |v};
            end else begin
                kept = v >> n;
                shr_sticky = kept | {{(AW-1){1'b0}}, ((kept << n) != v)};
            end
        end
    endfunction

    reg [AW-1:0] pa, ca;
    reg          both_zero_sign;
    always @(*) begin
        pa = p_w;
        ca = c_w;
        top_exp = p_top;
        if (p_zero) begin
            pa = {AW{1'b0}};
            top_exp = c_top;
        end else if (c_zero) begin
            ca = {AW{1'b0}};
        end else if (!diff[EW]) begin                       // product is at least as high
            ca = shr_sticky(c_w, diff);
        end else begin
            pa = shr_sticky(p_w, -diff);
            top_exp = c_top;
        end
    end

    // Effective add or subtract; the larger magnitude sets the sign.
    wire subtract = (p_sign != c_sign) && !p_zero && !c_zero;
    wire p_ge_c   = (pa >= ca);
    always @(*) begin
        if (p_zero && c_zero) begin
            mag  = {(AW+1){1'b0}};
            sign = p_sign & c_sign;
        end else if (!subtract) begin
            mag  = {1'b0, pa} + {1'b0, ca};
            sign = p_zero ? c_sign : p_sign;
        end else if (p_ge_c) begin
            mag  = {1'b0, pa} - {1'b0, ca};
            sign = (pa == ca) ? 1'b0 : p_sign;              // exact cancellation is +0
        end else begin
            mag  = {1'b0, ca} - {1'b0, pa};
            sign = c_sign;
        end
        if (p_inf)                                          // an infinite term sets the sign
            sign = p_sign;
        else if (c_inf)
            sign = c_sign;
    end

    assign zero = !nan && !inf && (mag == 0);
endmodule


module fp_round #(
    parameter EXP_BITS  = 5,
    parameter MANT_BITS = 10,
    parameter W  = 1 + EXP_BITS + MANT_BITS,
    parameter M  = MANT_BITS + 1,
    parameter EW = EXP_BITS + 4,
    parameter AW = 2 * M + 3
) (
    input  wire [AW:0]          mag,
    input  wire signed [EW-1:0] top_exp,
    input  wire                 sign,
    input  wire                 zero,
    input  wire                 inf,
    input  wire                 nan,
    output reg  [W-1:0]         result
);
    localparam integer BIAS    = (1 << (EXP_BITS - 1)) - 1;
    localparam integer EXP_ONE = (1 << EXP_BITS) - 1;
    localparam integer EMIN    = 1 - BIAS;
    localparam integer EMAX    = EXP_ONE - 1 - BIAS;
    localparam integer LW      = $clog2(AW + 2);

    // Position of the leading one (mag is non-zero whenever it is used).
    reg [LW-1:0] lead;
    integer i;
    always @(*) begin
        lead = {LW{1'b0}};
        for (i = 0; i <= AW; i = i + 1)
            if (mag[i]) lead = LW'(i);
    end

    wire [AW:0] norm = mag << (AW - lead);                  // leading one at bit AW
    wire signed [EW:0] exp_lead = $signed({top_exp[EW-1], top_exp}) + $signed({1'b0, lead})
                                - $signed((EW+1)'(AW - 1));
    wire [M-1:0] sig    = norm[AW -: M];
    wire         rbit   = norm[AW - M];
    wire         sticky = |norm[AW - M - 1:0];
    wire         up     = rbit && (sticky || sig[0]);
    wire [M:0]   sig_r  = {1'b0, sig} + {{M{1'b0}}, up};
    wire         carry  = sig_r[M];
    wire signed [EW:0] exp_r = exp_lead + $signed({{EW{1'b0}}, carry});
    wire [MANT_BITS-1:0] frac = carry ? sig_r[M-1:1] : sig_r[MANT_BITS-1:0];
    wire [EW:0] ef = exp_r + $signed((EW+1)'(BIAS));

    always @(*) begin
        if (nan) begin
            result = {1'b0, {EXP_BITS{1'b1}}, 1'b1, {(MANT_BITS-1){1'b0}}};
        end else if (inf) begin
            result = {sign, {EXP_BITS{1'b1}}, {MANT_BITS{1'b0}}};
        end else if (zero || mag == 0) begin
            result = {sign, {(W-1){1'b0}}};
        end else if (exp_lead < $signed((EW+1)'(EMIN))) begin
            result = {sign, {(W-1){1'b0}}};                // tiny before rounding: flush
        end else if (exp_r > $signed((EW+1)'(EMAX))) begin
            result = {sign, {EXP_BITS{1'b1}}, {MANT_BITS{1'b0}}};
        end else begin
            result = {sign, ef[EXP_BITS-1:0], frac};
        end
    end
endmodule
