`default_nettype none
`timescale 1ns/1ns

// BIAS & ACTIVATION UNIT (FP16 / BF16)
// Rd = f(round(Rs + Rt)), with Rt the bias. The bias add is the fused
// multiply-add of fp_arith.sv with a multiplier of exactly 1.0, so Rs enters
// the adder as a product without a multiplier.
//
// Activation functions (instruction[9:8]):
//   00 none           y
//   01 ReLU           +0 if y is negative (including -0), else y
//   10 Leaky ReLU     y * 2^-7 if y is negative, else y. The scaling is exact;
//                     a result below the smallest normal becomes -0.
//   11 Clipped ReLU   NaN stays NaN; otherwise min(1.0, ReLU(y))
// NaN results are the canonical quiet NaN (sign 0), so ReLU and Leaky ReLU
// pass them through.
//
// Timing (rs/rt set at the end of DECODE and held):
//   end of REQUEST:     aligned registers <= fp_align(rs * 1.0, rt)
//   end of first WAIT:  sum registers     <= fp_addsub(aligned)
//   EXECUTE:            activation_out    <= f(fp_round(sum))
module fp_activation #(
    parameter EXP_BITS  = 5,
    parameter MANT_BITS = 10,
    parameter DATA_BITS = 1 + EXP_BITS + MANT_BITS
) (
    input wire clk,
    input wire reset,
    input wire enable,

    input wire [2:0] core_state,
    input wire activation_enable,
    input wire [1:0] activation_func,

    input wire [DATA_BITS-1:0] unbiased_activation,
    input wire [DATA_BITS-1:0] bias,

    output wire [DATA_BITS-1:0] activation_out
);
    localparam M       = MANT_BITS + 1;
    localparam EW      = EXP_BITS + 4;
    localparam AW      = 2 * M + 3;
    localparam integer BIAS    = (1 << (EXP_BITS - 1)) - 1;
    localparam integer EXP_ONE = (1 << EXP_BITS) - 1;
    localparam integer LEAKY_SHIFT = 7;

    localparam [DATA_BITS-1:0] ONE = BIAS << MANT_BITS;

    localparam [1:0] ACT_NONE         = 2'b00;
    localparam [1:0] ACT_RELU         = 2'b01;
    localparam [1:0] ACT_LEAKY_RELU   = 2'b10;
    localparam [1:0] ACT_CLIPPED_RELU = 2'b11;

    // x * 1.0 as an fp_mul result: significand {1, frac} placed one bit
    // below the product's top, exponent of the top bit = e(x) - BIAS + 1.
    wire [EXP_BITS-1:0]  xe = unbiased_activation[DATA_BITS-2 -: EXP_BITS];
    wire [MANT_BITS-1:0] xf = unbiased_activation[MANT_BITS-1:0];
    wire [2*M-1:0]       x_prod = {1'b0, 1'b1, xf, {(M-1){1'b0}}};
    wire signed [EW-1:0] x_top  = $signed({{(EW-EXP_BITS){1'b0}}, xe}) - $signed(EW'(BIAS - 1));
    wire                 x_zero = (xe == 0);
    wire                 x_inf  = (xe == EXP_ONE) && (xf == 0);
    wire                 x_nan  = (xe == EXP_ONE) && (xf != 0);

    wire [AW-1:0]        al_hi, al_lo;
    wire signed [EW-1:0] al_top;
    wire                 al_hi_sign, al_lo_sign, al_sub, al_zero, al_inf, al_inf_sign, al_nan;
    fp_align #(.EXP_BITS(EXP_BITS), .MANT_BITS(MANT_BITS)) u_align (
        .prod(x_prod), .p_top(x_top),
        .p_sign(unbiased_activation[DATA_BITS-1]), .p_zero(x_zero), .p_inf(x_inf), .p_nan(x_nan),
        .c(bias),
        .hi(al_hi), .lo(al_lo), .top_exp(al_top), .hi_sign(al_hi_sign), .lo_sign(al_lo_sign),
        .sub(al_sub), .zero(al_zero), .inf(al_inf), .inf_sign(al_inf_sign), .nan(al_nan)
    );

    reg [AW-1:0]        q_hi, q_lo;
    reg signed [EW-1:0] q_top;
    reg                 q_hi_sign, q_lo_sign, q_sub, q_zero, q_inf, q_inf_sign, q_nan;

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

    wire [DATA_BITS-1:0] y;
    fp_round #(.EXP_BITS(EXP_BITS), .MANT_BITS(MANT_BITS)) u_round (
        .mag(s_mag), .top_exp(s_top),
        .sign(s_sign), .zero(s_zero), .inf(s_inf), .nan(s_nan),
        .result(y)
    );

    always @(posedge clk) begin
        if (reset) begin
            q_hi  <= {AW{1'b0}};
            q_lo  <= {AW{1'b0}};
            q_top <= {EW{1'b0}};
            {q_hi_sign, q_lo_sign, q_sub, q_zero, q_inf, q_inf_sign, q_nan} <= 7'b0;
            s_mag <= {(AW+1){1'b0}};
            s_top <= {EW{1'b0}};
            {s_sign, s_zero, s_inf, s_nan} <= 4'b0;
        end else begin
            q_hi  <= al_hi;
            q_lo  <= al_lo;
            q_top <= al_top;
            {q_hi_sign, q_lo_sign, q_sub, q_zero, q_inf, q_inf_sign, q_nan} <=
                {al_hi_sign, al_lo_sign, al_sub, al_zero, al_inf, al_inf_sign, al_nan};
            s_mag <= add_mag;
            s_top <= add_top;
            {s_sign, s_zero, s_inf, s_nan} <= {add_sign, add_zero, add_inf, add_nan};
        end
    end

    // Activation functions on y
    wire                 y_neg = y[DATA_BITS-1];
    wire [EXP_BITS-1:0]  ye    = y[DATA_BITS-2 -: EXP_BITS];
    wire                 y_nan = (ye == EXP_ONE) && (y[MANT_BITS-1:0] != 0);

    wire [DATA_BITS-1:0] relu_out  = y_neg ? {DATA_BITS{1'b0}} : y;
    wire [DATA_BITS-1:0] leaky_neg =
        (ye == EXP_ONE)    ? y :                                            // -inf
        (ye > LEAKY_SHIFT) ? {1'b1, ye - EXP_BITS'(LEAKY_SHIFT), y[MANT_BITS-1:0]} :
                             {1'b1, {(DATA_BITS-1){1'b0}}};                 // -0
    wire [DATA_BITS-1:0] leaky_out = y_neg ? leaky_neg : y;
    wire [DATA_BITS-1:0] clip_out  = y_nan ? y :
                                     y_neg ? {DATA_BITS{1'b0}} :
                                     (y > ONE) ? ONE : y;                   // positive: bit order = value order

    wire [DATA_BITS-1:0] activated =
        (activation_func == ACT_RELU)         ? relu_out  :
        (activation_func == ACT_LEAKY_RELU)   ? leaky_out :
        (activation_func == ACT_CLIPPED_RELU) ? clip_out  :
                                                y;

    reg [DATA_BITS-1:0] activation_out_reg;
    assign activation_out = activation_out_reg;

    always @(posedge clk) begin
        if (reset) begin
            activation_out_reg <= {DATA_BITS{1'b0}};
        end else if (enable) begin
            if (core_state == 3'b101 && activation_enable)
                activation_out_reg <= activated;
        end
    end
endmodule
