`default_nettype none
`timescale 1ns/1ps

// v3 matrix-unit PEs for study S2 (docs/v3_gt2n.md): weight-stationary,
// TPU-style. The activation register forwards east and feeds the
// multiplier; the weight chain (w_out) shifts south on w_shift and w_swap
// copies it into the active weight, so the next tile loads while this one
// computes; the partial sum enters from the north and leaves south.
//
// The partial-sum path takes L register stages through a PE (SF: 1; FP: 2,
// 3 with ALIGN_STAGE), so the array skews row r's activations by r * L
// cycles. The product is registered a stage earlier, off that path.
// Datapath registers have no reset: they carry only streamed values.

// Weight registers: with CG = 0 they load on w_shift / w_swap from clk; with
// CG = 1 the block gates their clocks (clk_w, clk_a: v3_block) and they load
// on every edge of those. tok_out is w_swap one cycle later, for v3_block's
// wavefront swap (WAVE = 1), where it travels east with the activation; with
// WAVE = 0 nothing reads it and synthesis removes it.
//
// SF16 in (Q1.15 sign-magnitude, canonical zero). The 15 x 15 product (Q0.30)
// is truncated toward zero to FRAC fraction bits and added into an ACC_W-bit
// two's-complement saturating sum with FRAC fraction bits:
//   FRAC 15, ACC_W 16: the v2 PE's arithmetic (sat16)
//   FRAC 19, ACC_W 24: Q5.19 (SF24)
//   FRAC 23, ACC_W 28: Q5.23 (SF28)
//   FRAC 23, ACC_W 32: Q9.23 (SF32)
// TRUNC_K < 0 writes the product as a multiply; TRUNC_K >= 0 as the sum of
// its partial-product rows with the columns below TRUNC_K left out and COMP
// added (their expected value). COMP < 2^(30 - FRAC), so a zero operand
// still gives a zero product.
//
// MUL_ST = 2 takes the product over two stages, off the partial-sum path:
// rows 0-7 (with COMP) and rows 8-14 are summed and registered separately,
// and the next stage adds them. The product is the same, one cycle later.
//
// CT = 1 writes the product as an explicit carry-save tree (csa_trees.sv):
// the rows (and COMP) reduced by 3:2 compressors to two rows, then one plain
// add. With MUL_ST = 2 the two rows are what is registered.
module v3_pe_sf #(
    parameter FRAC    = 23,
    parameter ACC_W   = 32,
    parameter TRUNC_K = -1,
    parameter COMP    = 0,
    parameter CG      = 0,
    parameter MUL_ST  = 1,
    parameter CT      = 0
) (
    input  wire             clk,
    input  wire             clk_w,
    input  wire             clk_a,
    input  wire             w_shift,
    input  wire             w_swap,
    input  wire [15:0]      a_in,
    output reg  [15:0]      a_out,
    input  wire [15:0]      w_in,
    output reg  [15:0]      w_out,
    input  wire [ACC_W-1:0] psum_in,
    output reg  [ACC_W-1:0] psum_out,
    output reg              tok_out
);
    reg [15:0]     w_act;
    reg [FRAC-1:0] p_mag;
    reg            p_sign;

    wire [29:0] prod;
    generate
        if (CT) begin : g_ct
            localparam [29:0] KEEP = (TRUNC_K < 0) ? ~30'd0 : ~((30'd1 << TRUNC_K) - 30'd1);
            localparam NR = (TRUNC_K < 0) ? 15 : 16;
            wire [NR*30-1:0] rows;
            wire [29:0]      cs, cc;
            genvar i;
            for (i = 0; i < 15; i = i + 1) begin : g_row
                assign rows[i*30 +: 30] = ({15'b0, w_act[14:0]} << i) & {30{a_out[i]}} & KEEP;
            end
            if (TRUNC_K >= 0) begin : g_comp
                assign rows[15*30 +: 30] = 30'(COMP);
            end
            v3_csa #(.W(30), .NR(NR)) u_csa (.rows(rows), .s(cs), .c(cc));
            if (MUL_ST == 2) begin : g_two
                reg [29:0] h_s, h_c;
                reg        h_sign;
                always @(posedge clk) begin
                    h_s    <= cs;
                    h_c    <= cc;
                    h_sign <= a_out[15] ^ w_act[15];
                end
                assign prod = h_s + h_c;
                always @(posedge clk) begin
                    p_mag  <= prod[29 -: FRAC];
                    p_sign <= h_sign;
                end
            end else begin : g_one
                assign prod = cs + cc;
                always @(posedge clk) begin
                    p_mag  <= prod[29 -: FRAC];
                    p_sign <= a_out[15] ^ w_act[15];
                end
            end
        end else if (MUL_ST == 2) begin : g_mul2
            localparam H = 8;
            wire [29:0] lo, hi;
            if (TRUNC_K < 0) begin : g_mul
                assign lo = a_out[H-1:0] * w_act[14:0];
                assign hi = (a_out[14:H] * w_act[14:0]) << H;
            end else begin : g_rows
                localparam [29:0] KEEP = ~((30'd1 << TRUNC_K) - 30'd1);
                reg [29:0] sl, sh;
                integer i;
                always @(*) begin
                    sl = 30'(COMP);
                    sh = 30'd0;
                    for (i = 0; i < 15; i = i + 1)
                        if (i < H) sl = sl + (({15'b0, w_act[14:0]} << i) & {30{a_out[i]}} & KEEP);
                        else       sh = sh + (({15'b0, w_act[14:0]} << i) & {30{a_out[i]}} & KEEP);
                end
                assign lo = sl;
                assign hi = sh;
            end
            reg [29:0] h_lo, h_hi;
            reg        h_sign;
            always @(posedge clk) begin
                h_lo   <= lo;
                h_hi   <= hi;
                h_sign <= a_out[15] ^ w_act[15];
            end
            assign prod = h_lo + h_hi;
            always @(posedge clk) begin
                p_mag  <= prod[29 -: FRAC];
                p_sign <= h_sign;
            end
        end else begin : g_mul1
            if (TRUNC_K < 0) begin : g_mul
                assign prod = a_out[14:0] * w_act[14:0];
            end else begin : g_rows
                localparam [29:0] KEEP = ~((30'd1 << TRUNC_K) - 30'd1);
                reg [29:0] s;
                integer i;
                always @(*) begin
                    s = 30'(COMP);
                    for (i = 0; i < 15; i = i + 1)
                        s = s + (({15'b0, w_act[14:0]} << i) & {30{a_out[i]}} & KEEP);
                end
                assign prod = s;
            end
            always @(posedge clk) begin
                p_mag  <= prod[29 -: FRAC];
                p_sign <= a_out[15] ^ w_act[15];
            end
        end
        if (CG) begin : g_cg
            always @(posedge clk_w) w_out <= w_in;
            always @(posedge clk_a) w_act <= w_out;
        end else begin : g_en
            always @(posedge clk) begin
                if (w_shift) w_out <= w_in;
                if (w_swap)  w_act <= w_out;
            end
        end
    endgenerate

    wire signed [ACC_W:0] term = p_sign ? -$signed({{(ACC_W+1-FRAC){1'b0}}, p_mag})
                                        :  $signed({{(ACC_W+1-FRAC){1'b0}}, p_mag});
    wire signed [ACC_W:0] sum  = $signed({psum_in[ACC_W-1], psum_in}) + term;
    wire ovf = sum[ACC_W] ^ sum[ACC_W-1];
    wire [ACC_W-1:0] sat = ovf ? {sum[ACC_W], {(ACC_W-1){!sum[ACC_W]}}} : sum[ACC_W-1:0];

    always @(posedge clk) begin
        a_out <= a_in;
        tok_out <= w_swap;
        psum_out <= sat;
    end
endmodule


// FP16 or BF16 in (IN_E/IN_M), partial sums in ACC_E/ACC_M:
//   psum_out = round(a * w + psum_in), one rounding to the accumulator's
//   format, with fp_arith.sv's semantics (RNE, flush to zero, overflow to
//   infinity, canonical NaN). IN = ACC is the v2 PE's arithmetic.
// Stages: multiply | align, add (| with ALIGN_STAGE) | normalise, round.
// TRUNC_K / COMP as in v3_pe_sf, on the significand product (fpx_mul).
// MUL_ST = 2 as in v3_pe_sf: the significand product's rows in two halves
// (CT = 1: the carry-save tree's two rows), registered with the exponent and
// flags, added in the next stage.
module v3_pe_fp #(
    parameter IN_E  = 5,
    parameter IN_M  = 10,
    parameter ACC_E = 8,
    parameter ACC_M = 23,
    parameter ALIGN_STAGE = 0,
    parameter TRUNC_K = -1,
    parameter COMP    = 0,
    parameter CG      = 0,
    parameter MUL_ST  = 1,
    parameter CT      = 0,
    parameter IW = 1 + IN_E + IN_M,
    parameter CW = 1 + ACC_E + ACC_M
) (
    input  wire          clk,
    input  wire          clk_w,
    input  wire          clk_a,
    input  wire          w_shift,
    input  wire          w_swap,
    input  wire [IW-1:0] a_in,
    output reg  [IW-1:0] a_out,
    input  wire [IW-1:0] w_in,
    output reg  [IW-1:0] w_out,
    input  wire [CW-1:0] psum_in,
    output reg  [CW-1:0] psum_out,
    output reg           tok_out
);
    localparam Mi   = IN_M + 1;
    localparam Ma   = ACC_M + 1;
    localparam AW_P = 2 * Mi + 3;
    localparam AW_A = Ma + 4;
    localparam AW   = (AW_P > AW_A) ? AW_P : AW_A;
    localparam EW   = ((IN_E > ACC_E) ? IN_E : ACC_E) + 4;

    reg [IW-1:0] w_act;

    wire [2*Mi-1:0]      mul_prod, mul_lo, mul_hi;
    wire signed [EW-1:0] mul_top;
    wire                 mul_sign, mul_zero, mul_inf, mul_nan;
    fpx_mul #(.EXP_BITS(IN_E), .MANT_BITS(IN_M), .EW(EW), .TRUNC_K(TRUNC_K), .COMP(COMP),
              .SPLIT(MUL_ST == 2), .CT(CT)) u_mul (
        .a(a_out), .b(w_act),
        .prod(mul_prod), .prod_lo(mul_lo), .prod_hi(mul_hi), .top_exp(mul_top),
        .sign(mul_sign), .zero(mul_zero), .inf(mul_inf), .nan(mul_nan)
    );

    reg [2*Mi-1:0]      p_prod;
    reg signed [EW-1:0] p_top;
    reg                 p_sign, p_zero, p_inf, p_nan;

    generate
        if (MUL_ST == 2) begin : g_mul2
            reg [2*Mi-1:0]      h_lo, h_hi;
            reg signed [EW-1:0] h_top;
            reg                 h_sign, h_zero, h_inf, h_nan;
            always @(posedge clk) begin
                h_lo  <= mul_lo;
                h_hi  <= mul_hi;
                h_top <= mul_top;
                {h_sign, h_zero, h_inf, h_nan} <= {mul_sign, mul_zero, mul_inf, mul_nan};
                p_prod <= h_lo + h_hi;
                p_top  <= h_top;
                {p_sign, p_zero, p_inf, p_nan} <= {h_sign, h_zero, h_inf, h_nan};
            end
        end else begin : g_mul1
            always @(posedge clk) begin
                p_prod <= mul_prod;
                p_top  <= mul_top;
                {p_sign, p_zero, p_inf, p_nan} <= {mul_sign, mul_zero, mul_inf, mul_nan};
            end
        end
    endgenerate

    wire [AW-1:0]        al_hi, al_lo;
    wire signed [EW-1:0] al_top;
    wire                 al_hi_sign, al_lo_sign, al_sub, al_zero, al_inf, al_inf_sign, al_nan;
    fpx_align #(.IN_E(IN_E), .IN_M(IN_M), .ACC_E(ACC_E), .ACC_M(ACC_M)) u_align (
        .prod(p_prod), .p_top(p_top),
        .p_sign(p_sign), .p_zero(p_zero), .p_inf(p_inf), .p_nan(p_nan),
        .c(psum_in),
        .hi(al_hi), .lo(al_lo), .top_exp(al_top), .hi_sign(al_hi_sign), .lo_sign(al_lo_sign),
        .sub(al_sub), .zero(al_zero), .inf(al_inf), .inf_sign(al_inf_sign), .nan(al_nan)
    );

    wire [AW-1:0]        ad_hi, ad_lo;
    wire signed [EW-1:0] ad_top;
    wire                 ad_hi_sign, ad_lo_sign, ad_sub, ad_zero, ad_inf, ad_inf_sign, ad_nan;
    generate
        if (ALIGN_STAGE) begin : g_align_reg
            reg [AW-1:0]        r_hi, r_lo;
            reg signed [EW-1:0] r_top;
            reg                 r_hi_sign, r_lo_sign, r_sub, r_zero, r_inf, r_inf_sign, r_nan;
            always @(posedge clk) begin
                r_hi  <= al_hi;
                r_lo  <= al_lo;
                r_top <= al_top;
                {r_hi_sign, r_lo_sign, r_sub, r_zero, r_inf, r_inf_sign, r_nan} <=
                    {al_hi_sign, al_lo_sign, al_sub, al_zero, al_inf, al_inf_sign, al_nan};
            end
            assign {ad_hi, ad_lo, ad_top} = {r_hi, r_lo, r_top};
            assign {ad_hi_sign, ad_lo_sign, ad_sub, ad_zero, ad_inf, ad_inf_sign, ad_nan} =
                {r_hi_sign, r_lo_sign, r_sub, r_zero, r_inf, r_inf_sign, r_nan};
        end else begin : g_align_comb
            assign {ad_hi, ad_lo, ad_top} = {al_hi, al_lo, al_top};
            assign {ad_hi_sign, ad_lo_sign, ad_sub, ad_zero, ad_inf, ad_inf_sign, ad_nan} =
                {al_hi_sign, al_lo_sign, al_sub, al_zero, al_inf, al_inf_sign, al_nan};
        end
    endgenerate

    wire [AW:0]          add_mag;
    wire signed [EW-1:0] add_top;
    wire                 add_sign, add_zero, add_inf, add_nan;
    fp_addsub #(.EXP_BITS(ACC_E), .MANT_BITS(ACC_M), .EW(EW), .AW(AW)) u_addsub (
        .hi(ad_hi), .lo(ad_lo), .in_top(ad_top), .hi_sign(ad_hi_sign), .lo_sign(ad_lo_sign),
        .sub(ad_sub), .in_zero(ad_zero), .in_inf(ad_inf), .inf_sign(ad_inf_sign), .in_nan(ad_nan),
        .mag(add_mag), .top_exp(add_top),
        .sign(add_sign), .zero(add_zero), .inf(add_inf), .nan(add_nan)
    );

    reg [AW:0]          s_mag;
    reg signed [EW-1:0] s_top;
    reg                 s_sign, s_zero, s_inf, s_nan;

    wire [CW-1:0] rounded;
    fp_round #(.EXP_BITS(ACC_E), .MANT_BITS(ACC_M), .EW(EW), .AW(AW)) u_round (
        .mag(s_mag), .top_exp(s_top),
        .sign(s_sign), .zero(s_zero), .inf(s_inf), .nan(s_nan),
        .result(rounded)
    );

    generate
        if (CG) begin : g_cg
            always @(posedge clk_w) w_out <= w_in;
            always @(posedge clk_a) w_act <= w_out;
        end else begin : g_en
            always @(posedge clk) begin
                if (w_shift) w_out <= w_in;
                if (w_swap)  w_act <= w_out;
            end
        end
    endgenerate

    always @(posedge clk) begin
        a_out <= a_in;
        tok_out <= w_swap;
        s_mag  <= add_mag;
        s_top  <= add_top;
        {s_sign, s_zero, s_inf, s_nan} <= {add_sign, add_zero, add_inf, add_nan};
        psum_out <= rounded;
    end
endmodule
