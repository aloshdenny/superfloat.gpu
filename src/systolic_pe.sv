`default_nettype none
`timescale 1ns/1ns

// OPTIMIZED SYSTOLIC ARRAY PROCESSING ELEMENT (Q1.15 Fixed-Point)
// Following the FMA diagram architecture for optimized MAC:
// - Sign XOR for product sign determination
// - 15-bit x 15-bit unsigned mantissa multiplication (smaller multiplier)
// - Weight-stationary dataflow: weights loaded once, activations flow through
// - 24-bit accumulator (reduced from 32-bit, sufficient for typical matmul depths)
// - Pipeline registers for systolic data flow
module systolic_pe #(
    parameter DATA_BITS = 16,  // Q1.15 fixed-point width
    parameter ACC_BITS = 24    // Reduced accumulator width
) (
    input wire clk,
    input wire reset,
    input wire enable,

    // Control signals
    input wire clear_acc,           // Clear accumulator
    input wire load_weight,         // Load weight into stationary register
    input wire compute_enable,      // Enable MAC computation

    // Data inputs (from west and north neighbors)
    input wire [DATA_BITS-1:0] a_in,    // Activation input (west to east)
    input wire [DATA_BITS-1:0] b_in,    // Weight/data input (north to south)

    // Data outputs (to east and south neighbors)
    output reg [DATA_BITS-1:0] a_out,   // Activation output (1 cycle delay)
    output reg [DATA_BITS-1:0] b_out,   // Weight output (1 cycle delay)

    // Accumulator output
    output wire [DATA_BITS-1:0] acc_out
);
    // Q1.15 saturation constants
    localparam [DATA_BITS-1:0] Q115_MAX = 16'h7FFF;
    localparam [DATA_BITS-1:0] Q115_MIN = 16'h8000;

    // Pipeline notes
    // - Stage 0: register |a|, |w|, and product sign (accepts 1/cycle)
    // - Stage 1: 15x15 multiply, register the Q1.15-aligned mantissa
    // - Stage 2: sign/extend + accumulate (only a narrow adder is on the feedback path)
    localparam int unsigned MAC_PIPE_LATENCY = 2;  // cycles from compute_enable to accumulator update

    // Registers (optimized)
    reg [DATA_BITS-1:0] weight_reg;        // Stationary weight (R2 equivalent)
    reg signed [ACC_BITS-1:0] accumulator; // Reduced-width accumulator

    // ============================================
    // Optimized MAC using sign-magnitude approach
    // ============================================

    // --------
    // Stage 0
    // --------
    wire sign_a_s0 = a_in[15];
    wire sign_w_s0 = weight_reg[15];
    wire sign_product_s0 = sign_a_s0 ^ sign_w_s0;  // XOR for product sign

    wire [14:0] mantissa_a_s0 = sign_a_s0 ? (~a_in[14:0] + 1'b1) : a_in[14:0];
    wire [14:0] mantissa_w_s0 = sign_w_s0 ? (~weight_reg[14:0] + 1'b1) : weight_reg[14:0];

    reg valid_s0;
    reg sign_product_s0_r;
    reg [14:0] mantissa_a_s0_r;
    reg [14:0] mantissa_w_s0_r;

    // --------
    // Stage 1
    // --------
    wire [29:0] product_unsigned_s1 = mantissa_a_s0_r * mantissa_w_s0_r;  // 15x15 unsigned multiply
    wire [14:0] product_mantissa_s1 = product_unsigned_s1[29:15];        // Q1.15-aligned mantissa

    reg valid_s1;
    reg sign_product_s1_r;
    reg [14:0] product_mantissa_s1_r;

    // --------
    // Stage 2 (accumulate)
    // --------
    wire [DATA_BITS-1:0] product_unsigned_16_s2 = {1'b0, product_mantissa_s1_r};
    wire signed [DATA_BITS-1:0] product_signed_s2 =
        sign_product_s1_r ? -$signed(product_unsigned_16_s2) : $signed(product_unsigned_16_s2);

    wire signed [ACC_BITS-1:0] product_extended_s2 =
        {{(ACC_BITS-DATA_BITS){product_signed_s2[DATA_BITS-1]}}, product_signed_s2};
    wire signed [ACC_BITS-1:0] acc_sum_s2 = accumulator + product_extended_s2;

    // ============================================
    // Output saturation (convert back to Q1.15)
    // ============================================
    wire signed [ACC_BITS-1:0] acc_shifted = accumulator; // Already in Q1.15 scale
    
    // Check for saturation
    wire sat_positive = (accumulator > $signed({{(ACC_BITS-DATA_BITS){1'b0}}, Q115_MAX}));
    wire sat_negative = (accumulator < $signed({{(ACC_BITS-DATA_BITS){1'b1}}, Q115_MIN}));
    
    assign acc_out = sat_positive ? Q115_MAX :
                     sat_negative ? Q115_MIN :
                     accumulator[DATA_BITS-1:0];

    // ============================================
    // Sequential logic
    // ============================================
    always @(posedge clk) begin
        if (reset) begin
            a_out <= {DATA_BITS{1'b0}};
            b_out <= {DATA_BITS{1'b0}};
            weight_reg <= {DATA_BITS{1'b0}};
            accumulator <= {ACC_BITS{1'b0}};
            valid_s0 <= 1'b0;
            valid_s1 <= 1'b0;
            sign_product_s0_r <= 1'b0;
            mantissa_a_s0_r <= 15'b0;
            mantissa_w_s0_r <= 15'b0;
            sign_product_s1_r <= 1'b0;
            product_mantissa_s1_r <= 15'b0;
        end else if (enable) begin
            // Systolic data flow: pass inputs with 1 cycle delay
            a_out <= a_in;
            b_out <= b_in;

            // Load weight into stationary register
            if (load_weight) begin
                weight_reg <= b_in;
            end

            // Pipeline + accumulator control
            if (clear_acc) begin
                accumulator <= {ACC_BITS{1'b0}};
                valid_s0 <= 1'b0;
                valid_s1 <= 1'b0;
            end else begin
                // Stage 0 registers (accept 1/cycle)
                valid_s0 <= compute_enable;
                sign_product_s0_r <= sign_product_s0;
                mantissa_a_s0_r <= mantissa_a_s0;
                mantissa_w_s0_r <= mantissa_w_s0;

                // Stage 1 registers
                valid_s1 <= valid_s0;
                sign_product_s1_r <= sign_product_s0_r;
                product_mantissa_s1_r <= product_mantissa_s1;

                // Stage 2: accumulate (narrow feedback adder only)
                if (valid_s1) begin
                    accumulator <= acc_sum_s2;
                end
            end
        end
    end
endmodule
