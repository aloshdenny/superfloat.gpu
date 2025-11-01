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

    // Registers (optimized)
    reg [DATA_BITS-1:0] weight_reg;        // Stationary weight (R2 equivalent)
    reg signed [ACC_BITS-1:0] accumulator; // Reduced-width accumulator

    // ============================================
    // Optimized MAC using sign-magnitude approach
    // ============================================
    
    // Sign bits
    wire sign_a = a_in[15];
    wire sign_w = weight_reg[15];
    wire sign_product = sign_a ^ sign_w;  // XOR for product sign

    // 15-bit mantissa extraction (absolute values)
    wire [14:0] mantissa_a = sign_a ? (~a_in[14:0] + 1'b1) : a_in[14:0];
    wire [14:0] mantissa_w = sign_w ? (~weight_reg[14:0] + 1'b1) : weight_reg[14:0];

    // 15x15 unsigned multiplication = 30-bit result
    wire [29:0] product_unsigned = mantissa_a * mantissa_w;

    // Extract Q1.15 portion (shift right 15)
    wire [14:0] product_mantissa = product_unsigned[29:15];

    // Reconstruct signed product
    wire [DATA_BITS-1:0] product_unsigned_16 = {1'b0, product_mantissa};
    wire signed [DATA_BITS-1:0] product_signed = sign_product ? 
                                                  -$signed(product_unsigned_16) : 
                                                  $signed(product_unsigned_16);

    // ============================================
    // Accumulation with reduced bit width
    // ============================================
    wire signed [ACC_BITS-1:0] product_extended = {{(ACC_BITS-DATA_BITS){product_signed[DATA_BITS-1]}}, product_signed};
    wire signed [ACC_BITS-1:0] acc_sum = accumulator + product_extended;

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
        end else if (enable) begin
            // Systolic data flow: pass inputs with 1 cycle delay
            a_out <= a_in;
            b_out <= b_in;

            // Load weight into stationary register
            if (load_weight) begin
                weight_reg <= b_in;
            end

            // Accumulator control
            if (clear_acc) begin
                accumulator <= {ACC_BITS{1'b0}};
            end else if (compute_enable) begin
                // MAC: acc = acc + (a_in * weight)
                accumulator <= acc_sum;
            end
        end
    end
endmodule
