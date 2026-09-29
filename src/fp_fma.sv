`default_nettype none
`timescale 1ns/1ns

// FUSED MULTIPLY-ADD UNIT (FP16 / BF16)
// Rd = round(Rs * Rt + Rd), one rounding, as defined in fp_arith.sv.
// Same interface and EXECUTE timing as the SF16 fma unit, so the scheduler
// is unchanged. rs/rt/rq are the core's operand registers, set at the end
// of DECODE and held until the next DECODE:
//   end of REQUEST:     product registers <= fp_mul(rs, rt)
//   end of first WAIT:  aligned registers <= fp_align(product, rq)
//   EXECUTE cycle 0:    sum registers     <= fp_addsub(aligned)
//   EXECUTE cycle 1:    fma_out           <= fp_round(sum)
// The product, aligned and sum registers run every cycle; with the operands
// held they settle in order and stay put until the next DECODE.
module fp_fma #(
    parameter EXP_BITS  = 5,
    parameter MANT_BITS = 10,
    parameter DATA_BITS = 1 + EXP_BITS + MANT_BITS
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

    // Align stage
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

    reg [AW-1:0]        q_hi, q_lo;
    reg signed [EW-1:0] q_top;
    reg                 q_hi_sign, q_lo_sign, q_sub, q_zero, q_inf, q_inf_sign, q_nan;

    // Sum stage
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

    always @(posedge clk) begin
        if (reset) begin
            p_prod <= {(2*M){1'b0}};
            p_top  <= {EW{1'b0}};
            {p_sign, p_zero, p_inf, p_nan} <= 4'b0;
            q_hi   <= {AW{1'b0}};
            q_lo   <= {AW{1'b0}};
            q_top  <= {EW{1'b0}};
            {q_hi_sign, q_lo_sign, q_sub, q_zero, q_inf, q_inf_sign, q_nan} <= 7'b0;
            s_mag  <= {(AW+1){1'b0}};
            s_top  <= {EW{1'b0}};
            {s_sign, s_zero, s_inf, s_nan} <= 4'b0;
        end else begin
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
        end
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
