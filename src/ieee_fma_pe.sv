// =============================================================================
// IEEE-754 fused multiply-add PE (HardFloat-class datapath)
// Weight-stationary systolic PE — same pinout as SF16 systolic_pe.
//
// Classic open FMA (Berkeley HardFloat / GPU ALU style):
//   S0 : register A/W
//   S1 : mantissa multiply + product exponent          → R3
//   S2 : exponent-diff align (barrel) + add/sub        → R4a (mag)
//   S3 : LZD + normalize + RNE + pack                  → R4  (acc)
//
// Subnormals flushed to zero. Inf/NaN handled.
// =============================================================================
`default_nettype none
`timescale 1ns / 1ps

module ieee_fma_pe #(
    parameter EXP_BITS  = 5,
    parameter MANT_BITS = 10,
    parameter DATA_BITS = 1 + EXP_BITS + MANT_BITS
) (
    input  wire                  clk,
    input  wire                  reset,
    input  wire                  enable,
    input  wire                  clear_acc,
    input  wire                  load_weight,
    input  wire                  compute_enable,
    input  wire [DATA_BITS-1:0]  a_in,
    input  wire [DATA_BITS-1:0]  b_in,
    output reg  [DATA_BITS-1:0]  a_out,
    output reg  [DATA_BITS-1:0]  b_out,
    output wire [DATA_BITS-1:0]  acc_out
);

    localparam MANT_W   = MANT_BITS + 1;
    localparam PROD_W   = 2 * MANT_W;
    localparam ALIGN_W  = PROD_W + 4;
    localparam EXP_MAX  = (1 << EXP_BITS) - 1;
    localparam EXP_BIAS = (1 << (EXP_BITS - 1)) - 1;
    localparam LZC_W    = $clog2(ALIGN_W + 2);

    // R2 weight
    reg                 r2_sign;
    reg [EXP_BITS-1:0]  r2_exp;
    reg [MANT_W-1:0]    r2_mant;
    reg                 r2_inf, r2_nan;
    reg                 valid_s0;

    // R3 product
    reg                 r3_sign;
    reg signed [EXP_BITS+2:0] r3_exp;
    reg [PROD_W-1:0]    r3_prod;
    reg                 r3_inf, r3_nan, r3_zero;
    reg                 valid_s1;

    // R4a aligned sum (before normalize)
    reg [ALIGN_W:0]           r4a_mag;
    reg                       r4a_sign;
    reg signed [EXP_BITS+2:0] r4a_exp;
    reg                       r4a_inf, r4a_nan, r4a_zero;
    reg                       valid_s2;

    // R4 accumulator
    reg [DATA_BITS-1:0] r4_acc;
    assign acc_out = r4_acc;

    // ---- unpack B ----
    wire        b_s = b_in[DATA_BITS-1];
    wire [EXP_BITS-1:0] b_e = b_in[DATA_BITS-2 -: EXP_BITS];
    wire [MANT_BITS-1:0] b_f = b_in[MANT_BITS-1:0];
    wire b_zero = (b_e == 0) && (b_f == 0);
    wire b_sub  = (b_e == 0) && (b_f != 0);
    wire b_inf  = (b_e == EXP_MAX) && (b_f == 0);
    wire b_nan  = (b_e == EXP_MAX) && (b_f != 0);
    wire [MANT_W-1:0] b_mant_u = (b_zero || b_sub) ? {MANT_W{1'b0}} : {1'b1, b_f};
    wire [EXP_BITS-1:0] b_exp_u = (b_zero || b_sub) ? {EXP_BITS{1'b0}} : b_e;

    // ---- S1 multiply ----
    wire        a_s = a_out[DATA_BITS-1];
    wire [EXP_BITS-1:0] a_e = a_out[DATA_BITS-2 -: EXP_BITS];
    wire [MANT_BITS-1:0] a_f = a_out[MANT_BITS-1:0];
    wire a_zero = (a_e == 0) && (a_f == 0);
    wire a_sub  = (a_e == 0) && (a_f != 0);
    wire a_inf  = (a_e == EXP_MAX) && (a_f == 0);
    wire a_nan  = (a_e == EXP_MAX) && (a_f != 0);
    wire [MANT_W-1:0] a_mant_u = (a_zero || a_sub) ? {MANT_W{1'b0}} : {1'b1, a_f};
    wire [EXP_BITS-1:0] a_exp_u = (a_zero || a_sub) ? {EXP_BITS{1'b0}} : a_e;

    wire [PROD_W-1:0] s1_prod = a_mant_u * r2_mant;
    wire              s1_sign = a_s ^ r2_sign;
    wire signed [EXP_BITS+2:0] s1_exp =
        $signed({{3{1'b0}}, a_exp_u}) + $signed({{3{1'b0}}, r2_exp}) - EXP_BIAS;
    wire s1_zero = (a_mant_u == 0) || (r2_mant == 0);
    wire s1_nan  = a_nan || r2_nan || (a_inf && (r2_mant == 0)) || (r2_inf && (a_mant_u == 0));
    wire s1_inf  = !s1_nan && (a_inf || r2_inf);

    // ---- S2 align + add (into combo → R4a) ----
    wire        c_s = r4_acc[DATA_BITS-1];
    wire [EXP_BITS-1:0] c_e = r4_acc[DATA_BITS-2 -: EXP_BITS];
    wire [MANT_BITS-1:0] c_f = r4_acc[MANT_BITS-1:0];
    wire c_zero = (c_e == 0) && (c_f == 0);
    wire c_inf  = (c_e == EXP_MAX) && (c_f == 0);
    wire c_nan  = (c_e == EXP_MAX) && (c_f != 0);
    wire [MANT_W-1:0] c_mant_u = c_zero ? {MANT_W{1'b0}} : {1'b1, c_f};

    wire [ALIGN_W-1:0] prod_ext = {r3_prod, {(ALIGN_W - PROD_W){1'b0}}};
    wire [ALIGN_W-1:0] add_ext  = {c_mant_u, {(ALIGN_W - MANT_W){1'b0}}};

    wire signed [EXP_BITS+2:0] p_exp = r3_exp;
    wire signed [EXP_BITS+2:0] c_exp = $signed({{3{1'b0}}, c_e});
    wire signed [EXP_BITS+3:0] d_exp = p_exp - c_exp;

    function automatic [ALIGN_W-1:0] rshift_sticky;
        input [ALIGN_W-1:0] val;
        input integer       amt;
        integer k;
        reg [ALIGN_W-1:0] tmp;
        reg sticky;
        begin
            if (amt <= 0) begin
                rshift_sticky = val;
            end else if (amt >= ALIGN_W) begin
                rshift_sticky = {|val, {(ALIGN_W-1){1'b0}}};
            end else begin
                sticky = 1'b0;
                for (k = 0; k < ALIGN_W; k = k + 1)
                    if (k < amt) sticky = sticky | val[k];
                tmp = val >> amt;
                tmp[0] = tmp[0] | sticky;
                rshift_sticky = tmp;
            end
        end
    endfunction

    reg [ALIGN_W-1:0] prod_al, add_al;
    reg signed [EXP_BITS+2:0] sum_exp;
    always @(*) begin
        prod_al = prod_ext;
        add_al  = add_ext;
        sum_exp = p_exp;
        if (r3_zero && c_zero) begin
            prod_al = 0; add_al = 0; sum_exp = 0;
        end else if (r3_zero) begin
            prod_al = 0; add_al = add_ext; sum_exp = c_exp;
        end else if (c_zero) begin
            prod_al = prod_ext; add_al = 0; sum_exp = p_exp;
        end else if (d_exp >= 0) begin
            prod_al = prod_ext;
            add_al  = rshift_sticky(add_ext, d_exp);
            sum_exp = p_exp;
        end else begin
            prod_al = rshift_sticky(prod_ext, -d_exp);
            add_al  = add_ext;
            sum_exp = c_exp;
        end
    end

    reg [ALIGN_W:0] mag;
    reg             sum_sign;
    always @(*) begin
        mag = 0;
        sum_sign = 1'b0;
        if (r3_zero && c_zero) begin
            mag = 0; sum_sign = 1'b0;
        end else if (r3_zero && !c_zero) begin
            mag = {1'b0, add_al}; sum_sign = c_s;
        end else if (!r3_zero && c_zero) begin
            mag = {1'b0, prod_al}; sum_sign = r3_sign;
        end else if (r3_sign == c_s) begin
            mag = {1'b0, prod_al} + {1'b0, add_al}; sum_sign = r3_sign;
        end else if (prod_al >= add_al) begin
            mag = {1'b0, prod_al} - {1'b0, add_al}; sum_sign = r3_sign;
        end else begin
            mag = {1'b0, add_al} - {1'b0, prod_al}; sum_sign = c_s;
        end
    end

    wire s2_nan  = r3_nan || c_nan || (r3_inf && c_inf && (r3_sign != c_s));
    wire s2_inf  = !s2_nan && (r3_inf || c_inf);
    wire s2_zero = !s2_nan && !s2_inf && (mag == 0);

    // ---- S3 normalize from R4a ----
    integer li;
    reg [LZC_W-1:0] lzc;
    reg found;
    always @(*) begin
        lzc = ALIGN_W + 1;
        found = 1'b0;
        for (li = ALIGN_W; li >= 0; li = li - 1) begin
            if (!found && r4a_mag[li]) begin
                lzc = ALIGN_W - li;
                found = 1'b1;
            end
        end
    end

    reg [ALIGN_W:0] norm;
    reg signed [EXP_BITS+3:0] nexp;
    reg [MANT_BITS:0] mant_ext;
    reg guard, roundb, sticky, lsb, round_up;
    reg [EXP_BITS-1:0] oexp;
    reg [MANT_BITS-1:0] ofrac;
    reg [DATA_BITS-1:0] ieee_word;

    always @(*) begin
        norm      = {(ALIGN_W+1){1'b0}};
        nexp      = 0;
        mant_ext  = {(MANT_BITS+1){1'b0}};
        guard     = 1'b0;
        roundb    = 1'b0;
        sticky    = 1'b0;
        lsb       = 1'b0;
        round_up  = 1'b0;
        oexp      = {EXP_BITS{1'b0}};
        ofrac     = {MANT_BITS{1'b0}};
        ieee_word = {DATA_BITS{1'b0}};

        if (r4a_nan) begin
            ieee_word = {1'b0, {EXP_BITS{1'b1}}, 1'b1, {(MANT_BITS-1){1'b0}}};
        end else if (r4a_inf) begin
            ieee_word = {r4a_sign, {EXP_BITS{1'b1}}, {MANT_BITS{1'b0}}};
        end else if (r4a_zero) begin
            ieee_word = {r4a_sign, {(DATA_BITS-1){1'b0}}};
        end else begin
            norm = r4a_mag << lzc;
            nexp = r4a_exp - $signed({{(EXP_BITS+3-LZC_W){1'b0}}, lzc}) + 1;
            mant_ext = norm[ALIGN_W -: (MANT_BITS+1)];
            guard  = norm[ALIGN_W - (MANT_BITS+1)];
            roundb = norm[ALIGN_W - (MANT_BITS+2)];
            sticky = |(norm[ALIGN_W - (MANT_BITS+3):0]);
            lsb = mant_ext[0];
            round_up = guard & (roundb | sticky | lsb);
            ofrac = mant_ext[MANT_BITS-1:0];
            oexp  = nexp[EXP_BITS-1:0];
            if (round_up)
                {oexp, ofrac} = {oexp, ofrac} + 1'b1;
            if (nexp >= EXP_MAX)
                ieee_word = {r4a_sign, {EXP_BITS{1'b1}}, {MANT_BITS{1'b0}}};
            else if (nexp <= 0)
                ieee_word = {r4a_sign, {(DATA_BITS-1){1'b0}}};
            else
                ieee_word = {r4a_sign, oexp, ofrac};
        end
    end

    // ---- registers ----
    always @(posedge clk) begin
        if (reset) begin
            a_out <= 0; b_out <= 0;
            r2_sign <= 0; r2_exp <= 0; r2_mant <= 0; r2_inf <= 0; r2_nan <= 0;
            r3_sign <= 0; r3_exp <= 0; r3_prod <= 0;
            r3_inf <= 0; r3_nan <= 0; r3_zero <= 1;
            r4a_mag <= 0; r4a_sign <= 0; r4a_exp <= 0;
            r4a_inf <= 0; r4a_nan <= 0; r4a_zero <= 1;
            r4_acc <= 0;
            valid_s0 <= 0; valid_s1 <= 0; valid_s2 <= 0;
        end else if (enable) begin
            a_out <= a_in;
            b_out <= b_in;

            if (load_weight) begin
                r2_sign <= b_s;
                r2_exp  <= b_exp_u;
                r2_mant <= b_mant_u;
                r2_inf  <= b_inf;
                r2_nan  <= b_nan;
            end

            if (clear_acc) begin
                r3_sign <= 0; r3_exp <= 0; r3_prod <= 0;
                r3_inf <= 0; r3_nan <= 0; r3_zero <= 1;
                r4a_mag <= 0; r4a_sign <= 0; r4a_exp <= 0;
                r4a_inf <= 0; r4a_nan <= 0; r4a_zero <= 1;
                r4_acc <= 0;
                valid_s0 <= 0; valid_s1 <= 0; valid_s2 <= 0;
            end else begin
                valid_s0 <= compute_enable;
                valid_s1 <= valid_s0;
                valid_s2 <= valid_s1;

                r3_sign <= s1_sign;
                r3_exp  <= s1_exp;
                r3_prod <= s1_prod;
                r3_inf  <= s1_inf;
                r3_nan  <= s1_nan;
                r3_zero <= s1_zero;

                if (valid_s1) begin
                    r4a_mag  <= mag;
                    r4a_sign <= sum_sign;
                    r4a_exp  <= sum_exp;
                    r4a_inf  <= s2_inf;
                    r4a_nan  <= s2_nan;
                    r4a_zero <= s2_zero;
                end

                if (valid_s2)
                    r4_acc <= ieee_word;
            end
        end
    end
endmodule

module fp16_systolic_pe (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire        clear_acc,
    input  wire        load_weight,
    input  wire        compute_enable,
    input  wire [15:0] a_in,
    input  wire [15:0] b_in,
    output wire [15:0] a_out,
    output wire [15:0] b_out,
    output wire [15:0] acc_out
);
    ieee_fma_pe #(.EXP_BITS(5), .MANT_BITS(10)) u_fma (
        .clk(clk), .reset(reset), .enable(enable),
        .clear_acc(clear_acc), .load_weight(load_weight),
        .compute_enable(compute_enable),
        .a_in(a_in), .b_in(b_in),
        .a_out(a_out), .b_out(b_out), .acc_out(acc_out)
    );
endmodule

module fp32_systolic_pe (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire        clear_acc,
    input  wire        load_weight,
    input  wire        compute_enable,
    input  wire [31:0] a_in,
    input  wire [31:0] b_in,
    output wire [31:0] a_out,
    output wire [31:0] b_out,
    output wire [31:0] acc_out
);
    ieee_fma_pe #(.EXP_BITS(8), .MANT_BITS(23)) u_fma (
        .clk(clk), .reset(reset), .enable(enable),
        .clear_acc(clear_acc), .load_weight(load_weight),
        .compute_enable(compute_enable),
        .a_in(a_in), .b_in(b_in),
        .a_out(a_out), .b_out(b_out), .acc_out(acc_out)
    );
endmodule
