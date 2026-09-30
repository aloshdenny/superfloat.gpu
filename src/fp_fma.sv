`default_nettype none
`timescale 1ns/1ns

// FUSED MULTIPLY-ADD UNIT (FP16 / BF16)
// Rd = round(Rs * Rt + Rd), one rounding, as defined in fp_arith.sv.
// Same interface and EXECUTE timing as the SF16 fma unit, so the scheduler
// is unchanged. rs/rt/rq are the core's operand registers, set at the end
// of DECODE and held until the next DECODE:
//   end of REQUEST:     product registers <= fp_mul(rs, rt)
//   end of first WAIT:  sum registers     <= fp_addsub(fp_align(product, rq))
//   EXECUTE cycle 0:    (sum registers are settled)
//   EXECUTE cycle 1:    fma_out           <= fp_round(sum)
// With ALIGN_STAGE = 1 the aligned operands are registered at the end of the
// first WAIT and the sum at the end of EXECUTE cycle 0, which EXECUTE cycle 1
// then rounds (FP16: align and add together were its tile's critical path).
// The pipeline registers run every cycle; with the operands held they settle
// two (three with ALIGN_STAGE) cycles after DECODE and stay put until the
// next DECODE.
module fp_fma #(
    parameter EXP_BITS    = 5,
    parameter MANT_BITS   = 10,
    parameter ALIGN_STAGE = 0,               // 1: register between align and add
    parameter DATA_BITS   = 1 + EXP_BITS + MANT_BITS
) (
    input wire clk,
    input wire reset,
    input wire enable,

    input wire [2:0] core_state,
    input wire decoded_fma_enable,

    input wire [DATA_BITS-1:0] rs,    // activation
    input wire [DATA_BITS-1:0] rt,    // weight
    input wire [DATA_BITS-1:0] rq,    // accumulator (Rd)

    output wire [DATA_BITS-1:0] fma_out
);
    localparam M  = MANT_BITS + 1;
    localparam EW = EXP_BITS + 4;
    localparam AW = 2 * M + 3;

    // Product stage
    wire [2*M-1:0]       mul_prod;
    wire signed [EW-1:0] mul_top;
    wire                 mul_sign, mul_zero, mul_inf, mul_nan;
    fp_mul #(.EXP_BITS(EXP_BITS), .MANT_BITS(MANT_BITS)) u_mul (
        .a(rs), .b(rt),
        .prod(mul_prod), .top_exp(mul_top),
        .sign(mul_sign), .zero(mul_zero), .inf(mul_inf), .nan(mul_nan)
    );

    reg [2*M-1:0]       p_prod;
    reg signed [EW-1:0] p_top;
    reg                 p_sign, p_zero, p_inf, p_nan;

    // Sum stage: align, then add or subtract
    wire [AW-1:0]        al_hi, al_lo;
    wire signed [EW-1:0] al_top;
    wire                 al_hi_sign, al_lo_sign, al_sub, al_zero, al_inf, al_inf_sign, al_nan;
    fp_align #(.EXP_BITS(EXP_BITS), .MANT_BITS(MANT_BITS)) u_align (
        .prod(p_prod), .p_top(p_top),
        .p_sign(p_sign), .p_zero(p_zero), .p_inf(p_inf), .p_nan(p_nan),
        .c(rq),
        .hi(al_hi), .lo(al_lo), .top_exp(al_top), .hi_sign(al_hi_sign), .lo_sign(al_lo_sign),
        .sub(al_sub), .zero(al_zero), .inf(al_inf), .inf_sign(al_inf_sign), .nan(al_nan)
    );

    // Optional register between align and add (ALIGN_STAGE)
    wire [AW-1:0]        ad_hi, ad_lo;
    wire signed [EW-1:0] ad_top;
    wire                 ad_hi_sign, ad_lo_sign, ad_sub, ad_zero, ad_inf, ad_inf_sign, ad_nan;
    generate
        if (ALIGN_STAGE) begin : g_align_reg
            reg [AW-1:0]        r_hi, r_lo;
            reg signed [EW-1:0] r_top;
            reg                 r_hi_sign, r_lo_sign, r_sub, r_zero, r_inf, r_inf_sign, r_nan;
            always @(posedge clk) begin      // datapath only: no reset
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
    fp_addsub #(.EXP_BITS(EXP_BITS), .MANT_BITS(MANT_BITS)) u_addsub (
        .hi(ad_hi), .lo(ad_lo), .in_top(ad_top), .hi_sign(ad_hi_sign), .lo_sign(ad_lo_sign),
        .sub(ad_sub), .in_zero(ad_zero), .in_inf(ad_inf), .inf_sign(ad_inf_sign), .in_nan(ad_nan),
        .mag(add_mag), .top_exp(add_top),
        .sign(add_sign), .zero(add_zero), .inf(add_inf), .nan(add_nan)
    );

    reg [AW:0]          s_mag;
    reg signed [EW-1:0] s_top;
    reg                 s_sign, s_zero, s_inf, s_nan;

    // Round stage
    wire [DATA_BITS-1:0] rounded;
    fp_round #(.EXP_BITS(EXP_BITS), .MANT_BITS(MANT_BITS)) u_round (
        .mag(s_mag), .top_exp(s_top),
        .sign(s_sign), .zero(s_zero), .inf(s_inf), .nan(s_nan),
        .result(rounded)
    );

    reg [DATA_BITS-1:0] fma_out_reg;
    reg                 exec_phase;   // 0 = first EXECUTE cycle, 1 = second
    assign fma_out = fma_out_reg;

    // The pipeline registers carry no reset: they run every cycle from the
    // core's operand registers, and fma_out takes their result only in
    // EXECUTE, after they have settled. This keeps core_reset's fan-out small.
    always @(posedge clk) begin
        p_prod <= mul_prod;
        p_top  <= mul_top;
        {p_sign, p_zero, p_inf, p_nan} <= {mul_sign, mul_zero, mul_inf, mul_nan};
        s_mag  <= add_mag;
        s_top  <= add_top;
        {s_sign, s_zero, s_inf, s_nan} <= {add_sign, add_zero, add_inf, add_nan};
    end

    always @(posedge clk) begin
        if (reset) begin
            fma_out_reg <= {DATA_BITS{1'b0}};
            exec_phase  <= 1'b0;
        end else if (enable) begin
            if (core_state == 3'b101 && decoded_fma_enable) begin
                if (!exec_phase) begin
                    exec_phase <= 1'b1;
                end else begin
                    fma_out_reg <= rounded;
                    exec_phase  <= 1'b0;
                end
            end else begin
                exec_phase <= 1'b0;
            end
        end
    end
endmodule
