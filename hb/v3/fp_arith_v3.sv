`default_nettype none
`timescale 1ns/1ns

// IEEE-style 16-bit floating-point datapath (FP16: 5/10, BF16: 8/7)
//
// Four combinational stages that together compute round(a*b + c), the fused
// multiply-add used by the systolic PEs, the per-thread FMA units and the
// activation units. Callers place a register after each stage.
//
//   fp_mul   : exact significand product and its exponent
//   fp_align : order the product and the addend by exponent, shift the
//              smaller one right (sticky), classify NaN / infinity / zero
//   fp_addsub: add or subtract the aligned significands
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
// The adder window (AW bits) holds the full 2M-bit product plus three bits
// below it. When an operand is shifted far enough to lose bits, cancellation
// is limited to one bit, so a single sticky bit keeps the rounding exact.
// Both operands are placed with their weight-2^top bit at AW-1: the product
// as {prod, 000} (its top bit may be 0), the addend as {1, frac, 0...}.

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


module fp_align #(
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
    output reg  [AW-1:0]        hi,        // operand with the larger exponent
    output reg  [AW-1:0]        lo,        // the other, aligned to hi (sticky in bit 0)
    output reg  signed [EW-1:0] top_exp,   // unbiased exponent of bit AW-1
    output reg                  hi_sign,
    output reg                  lo_sign,
    output wire                 sub,       // effective subtraction of two non-zero terms
    output wire                 zero,      // both terms zero: result is (p_sign & c_sign) zero
    output wire                 inf,
    output wire                 inf_sign,
    output wire                 nan
);
    localparam integer BIAS    = (1 << (EXP_BITS - 1)) - 1;
    localparam integer EXP_ONE = (1 << EXP_BITS) - 1;
    localparam integer SW      = $clog2(AW + 1);             // bits of a clamped shift

    wire [EXP_BITS-1:0]  ce = c[W-2 -: EXP_BITS];
    wire [MANT_BITS-1:0] cf = c[MANT_BITS-1:0];
    wire c_sign = c[W-1];
    wire c_zero = (ce == 0);
    wire c_inf  = (ce == EXP_ONE) && (cf == 0);
    wire c_nan  = (ce == EXP_ONE) && (cf != 0);

    assign nan      = p_nan || c_nan || (p_inf && c_inf && (p_sign != c_sign));
    assign inf      = !nan && (p_inf || c_inf);
    assign inf_sign = p_inf ? p_sign : c_sign;
    assign zero     = p_zero && c_zero;
    assign sub      = (p_sign != c_sign) && !p_zero && !c_zero;

    wire [AW-1:0] p_w = {prod, 3'b000};
    wire [AW-1:0] c_w = {1'b1, cf, {M{1'b0}}, 3'b000};
    wire signed [EW-1:0] c_top = $signed({{(EW-EXP_BITS){1'b0}}, ce}) - $signed(EW'(BIAS));

    // Both differences in parallel; the sign of one picks the order.
    wire signed [EW:0] d_pc = $signed({p_top[EW-1], p_top}) - $signed({c_top[EW-1], c_top});
    wire signed [EW:0] d_cp = $signed({c_top[EW-1], c_top}) - $signed({p_top[EW-1], p_top});
    wire p_high = !d_pc[EW];                                  // p_top >= c_top
    wire [EW:0] span = p_high ? d_pc : d_cp;                  // >= 0
    wire [SW-1:0] shift = (span >= AW) ? SW'(AW) : span[SW-1:0];

    wire [AW-1:0] sh_in = p_high ? c_w : p_w;
    // Right shift with sticky: bits shifted out are ORed into bit 0.
    wire [AW-1:0] sh_out = sh_in >> shift;
    wire [AW-1:0] lost_mask  = ~({AW{1'b1}} << shift);
    wire          sh_sticky  = |(sh_in & lost_mask);

    always @(*) begin
        if (p_zero) begin                                     // result is c (or 0 + 0)
            hi = c_w;  lo = {AW{1'b0}};  top_exp = c_top;
            hi_sign = c_sign;  lo_sign = p_sign;          // 0 + 0 uses both signs
        end else if (c_zero) begin                            // result is the product
            hi = p_w;  lo = {AW{1'b0}};  top_exp = p_top;
            hi_sign = p_sign;  lo_sign = c_sign;
        end else if (p_high) begin
            hi = p_w;  lo = sh_out | {{(AW-1){1'b0}}, sh_sticky};  top_exp = p_top;
            hi_sign = p_sign;  lo_sign = c_sign;
        end else begin
            hi = c_w;  lo = sh_out | {{(AW-1){1'b0}}, sh_sticky};  top_exp = c_top;
            hi_sign = c_sign;  lo_sign = p_sign;
        end
    end
endmodule


module fp_addsub #(
    parameter EXP_BITS  = 5,
    parameter MANT_BITS = 10,
    parameter M  = MANT_BITS + 1,
    parameter EW = EXP_BITS + 4,
    parameter AW = 2 * M + 3
) (
    input  wire [AW-1:0]        hi,
    input  wire [AW-1:0]        lo,
    input  wire signed [EW-1:0] in_top,
    input  wire                 hi_sign,
    input  wire                 lo_sign,
    input  wire                 sub,
    input  wire                 in_zero,   // both terms zero
    input  wire                 in_inf,
    input  wire                 inf_sign,
    input  wire                 in_nan,
    output reg  [AW:0]          mag,       // bit AW is the carry
    output wire signed [EW-1:0] top_exp,   // unbiased exponent of mag[AW-1]
    output reg                  sign,
    output wire                 zero,      // exact zero result (sign valid)
    output wire                 inf,
    output wire                 nan
);
    wire [AW:0] sum   = {1'b0, hi} + {1'b0, lo};
    wire [AW:0] d_hl  = {1'b0, hi} - {1'b0, lo};
    wire [AW:0] d_lh  = {1'b0, lo} - {1'b0, hi};
    wire        equal = (hi == lo);

    assign top_exp = in_top;
    assign nan  = in_nan;
    assign inf  = !in_nan && in_inf;
    assign zero = !in_nan && !in_inf && (in_zero || (sub && equal));

    always @(*) begin
        if (!sub) begin
            mag  = sum;
            sign = hi_sign;
        end else if (!d_hl[AW]) begin                         // hi >= lo
            mag  = d_hl;
            sign = hi_sign;
        end else begin
            mag  = d_lh;
            sign = lo_sign;
        end
        if (in_inf)
            sign = inf_sign;                                  // an infinite term sets the sign
        else if (in_zero)
            sign = hi_sign & lo_sign;                     // 0 + 0: -0 only if both are -0
        else if (sub && equal)
            sign = 1'b0;                                      // exact cancellation is +0
    end
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
    localparam integer PW      = 32;                          // padded normaliser width
    localparam integer NW      = 5;                           // log2(PW)

    // Leading-zero count and normalising shift together, in log2(PW) steps:
    // each step tests the top half of what is left and shifts it out if zero.
    // mag is non-zero whenever the result is used.
    reg [PW-1:0] v;
    reg [NW-1:0] nlz;
    always @(*) begin
        v   = {mag, {(PW-AW-1){1'b0}}};
        nlz = {NW{1'b0}};
        if (v[31:16] == 0) begin v = v << 16; nlz[4] = 1'b1; end
        if (v[31:24] == 0) begin v = v << 8;  nlz[3] = 1'b1; end
        if (v[31:28] == 0) begin v = v << 4;  nlz[2] = 1'b1; end
        if (v[31:30] == 0) begin v = v << 2;  nlz[1] = 1'b1; end
        if (v[31]    == 0) begin v = v << 1;  nlz[0] = 1'b1; end
    end

    // The leading one of mag at bit AW-nlz weighs 2^(top_exp + 1 - nlz).
    wire signed [EW:0] exp_lead = $signed({top_exp[EW-1], top_exp}) + $signed((EW+1)'(1))
                                - $signed({{(EW+1-NW){1'b0}}, nlz});
    wire signed [EW:0] exp_up   = exp_lead + $signed((EW+1)'(1));

    wire [M-1:0] sig    = v[PW-1 -: M];
    wire         rbit   = v[PW-1-M];
    wire         sticky = |v[PW-2-M:0];
    wire         up     = rbit && (sticky || sig[0]);
    wire [M:0]   sig_r  = {1'b0, sig} + {{M{1'b0}}, up};
    wire         carry  = sig_r[M];                           // sig was all ones: 1.000 x 2^+1
    wire [MANT_BITS-1:0] frac = carry ? {MANT_BITS{1'b0}} : sig_r[MANT_BITS-1:0];

    wire tiny     = exp_lead < $signed((EW+1)'(EMIN));
    wire ovf_lead = exp_lead > $signed((EW+1)'(EMAX));
    wire ovf_up   = exp_up   > $signed((EW+1)'(EMAX));
    wire [EXP_BITS-1:0] ef_lead = EXP_BITS'(exp_lead + $signed((EW+1)'(BIAS)));
    wire [EXP_BITS-1:0] ef_up   = EXP_BITS'(exp_up + $signed((EW+1)'(BIAS)));

    always @(*) begin
        if (nan) begin
            result = {1'b0, {EXP_BITS{1'b1}}, 1'b1, {(MANT_BITS-1){1'b0}}};
        end else if (inf) begin
            result = {sign, {EXP_BITS{1'b1}}, {MANT_BITS{1'b0}}};
        end else if (zero || tiny) begin                      // tiny before rounding: flush
            result = {sign, {(W-1){1'b0}}};
        end else if (carry ? ovf_up : ovf_lead) begin
            result = {sign, {EXP_BITS{1'b1}}, {MANT_BITS{1'b0}}};
        end else begin
            result = {sign, carry ? ef_up : ef_lead, frac};
        end
    end
endmodule
