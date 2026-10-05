`default_nettype none
`timescale 1ns/1ps

// fp_align (src/fp_arith.sv) with the addend in its own, wider format: the
// product of two IN_E/IN_M operands meets an ACC_E/ACC_M accumulator, for
// the v3 PEs that accumulate FP16 or BF16 products in FP32 (study S2,
// docs/v3_gt2n.md). With IN = ACC it places both operands as fp_align does.
//
// The window is AW = max(2*Mi + 3, Ma + 4) bits. The product sits at the top
// with zeros below; the addend as {1, frac, zeros}. When the smaller operand
// loses bits, its leading one is at least five places below the window's
// top, so a subtraction cancels at most two leading places (the product's
// top bit may be 0) and the result still has Ma bits, a round bit and the
// sticky bit 0 in the window.
module fpx_align #(
    parameter IN_E  = 5,
    parameter IN_M  = 10,
    parameter ACC_E = 8,
    parameter ACC_M = 23,
    parameter Mi = IN_M + 1,
    parameter Ma = ACC_M + 1,
    parameter AW_P = 2 * Mi + 3,
    parameter AW_A = Ma + 4,
    parameter AW = (AW_P > AW_A) ? AW_P : AW_A,
    parameter EW = ((IN_E > ACC_E) ? IN_E : ACC_E) + 4,
    parameter CW = 1 + ACC_E + ACC_M
) (
    input  wire [2*Mi-1:0]      prod,
    input  wire signed [EW-1:0] p_top,
    input  wire                 p_sign,
    input  wire                 p_zero,
    input  wire                 p_inf,
    input  wire                 p_nan,
    input  wire [CW-1:0]        c,
    output reg  [AW-1:0]        hi,
    output reg  [AW-1:0]        lo,
    output reg  signed [EW-1:0] top_exp,
    output reg                  hi_sign,
    output reg                  lo_sign,
    output wire                 sub,
    output wire                 zero,
    output wire                 inf,
    output wire                 inf_sign,
    output wire                 nan
);
    localparam integer BIAS    = (1 << (ACC_E - 1)) - 1;
    localparam integer EXP_ONE = (1 << ACC_E) - 1;
    localparam integer SW      = $clog2(AW + 1);

    wire [ACC_E-1:0] ce = c[CW-2 -: ACC_E];
    wire [ACC_M-1:0] cf = c[ACC_M-1:0];
    wire c_sign = c[CW-1];
    wire c_zero = (ce == 0);
    wire c_inf  = (ce == EXP_ONE) && (cf == 0);
    wire c_nan  = (ce == EXP_ONE) && (cf != 0);

    assign nan      = p_nan || c_nan || (p_inf && c_inf && (p_sign != c_sign));
    assign inf      = !nan && (p_inf || c_inf);
    assign inf_sign = p_inf ? p_sign : c_sign;
    assign zero     = p_zero && c_zero;
    assign sub      = (p_sign != c_sign) && !p_zero && !c_zero;

    wire [AW-1:0] p_w = {prod, {(AW-2*Mi){1'b0}}};
    wire [AW-1:0] c_w = {1'b1, cf, {(AW-Ma){1'b0}}};
    wire signed [EW-1:0] c_top = $signed({{(EW-ACC_E){1'b0}}, ce}) - $signed(EW'(BIAS));

    wire signed [EW:0] d_pc = $signed({p_top[EW-1], p_top}) - $signed({c_top[EW-1], c_top});
    wire signed [EW:0] d_cp = $signed({c_top[EW-1], c_top}) - $signed({p_top[EW-1], p_top});
    wire p_high = !d_pc[EW];
    wire [EW:0] span = p_high ? d_pc : d_cp;
    wire [SW-1:0] shift = (span >= AW) ? SW'(AW) : span[SW-1:0];

    wire [AW-1:0] sh_in = p_high ? c_w : p_w;
    wire [AW-1:0] sh_out = sh_in >> shift;
    wire [AW-1:0] lost_mask = ~({AW{1'b1}} << shift);
    wire          sh_sticky = |(sh_in & lost_mask);

    always @(*) begin
        if (p_zero) begin
            hi = c_w;  lo = {AW{1'b0}};  top_exp = c_top;
            hi_sign = c_sign;  lo_sign = p_sign;
        end else if (c_zero) begin
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


// fp_mul (src/fp_arith.sv) with an optional truncated significand product:
// TRUNC_K >= 0 sums the partial-product rows with the columns below TRUNC_K
// left out and COMP added (as v3_pe_sf). TRUNC_K < 0 is fp_mul exactly.
module fpx_mul #(
    parameter EXP_BITS  = 5,
    parameter MANT_BITS = 10,
    parameter W  = 1 + EXP_BITS + MANT_BITS,
    parameter M  = MANT_BITS + 1,
    parameter EW = EXP_BITS + 4,
    parameter TRUNC_K = -1,
    parameter COMP    = 0
) (
    input  wire [W-1:0]         a,
    input  wire [W-1:0]         b,
    output wire [2*M-1:0]       prod,
    output wire signed [EW-1:0] top_exp,
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
    generate
        if (TRUNC_K < 0) begin : g_mul
            assign prod = am * bm;
        end else begin : g_rows
            localparam [2*M-1:0] ONE  = 1;
            localparam [2*M-1:0] KEEP = ~((ONE << TRUNC_K) - ONE);
            reg [2*M-1:0] s;
            integer i;
            always @(*) begin
                s = (2*M)'(COMP);
                for (i = 0; i < M; i = i + 1)
                    s = s + (({{M{1'b0}}, bm} << i) & {(2*M){am[i]}} & KEEP);
            end
            assign prod = s;
        end
    endgenerate
    assign top_exp = $signed({{(EW-EXP_BITS){1'b0}}, ae}) + $signed({{(EW-EXP_BITS){1'b0}}, be})
                   - $signed(EW'(2 * BIAS - 1));
endmodule
