`default_nettype none
`timescale 1ns/1ns

// BIAS & ACTIVATION (BA) UNIT (SF16 Fixed-Point, Sign-Magnitude)
// Following the diagram architecture:
// - R5: Bias register (16-bit)
// - Adder for bias addition
// - Activation function block (ReLU, Leaky ReLU, or pass-through)
// - Outputs final activation value
//
// Activation functions supported:
// - 00: Pass-through (no activation)
// - 01: ReLU (max(0, x))
// - 10: Leaky ReLU (x if x > 0, else 0.01*x)
// - 11: Clipped ReLU (min(1, max(0, x)))
module activation #(
    parameter DATA_BITS = 16  // SF16 fixed-point width
) (
    input wire clk,
    input wire reset,
    input wire enable,

    input wire [2:0] core_state,
    input wire activation_enable,        // Enable activation computation
    input wire [1:0] activation_func,    // Activation function select

    // Inputs
    input wire [DATA_BITS-1:0] unbiased_activation,  // From FMA unit (accumulated sum)
    input wire [DATA_BITS-1:0] bias,                  // Bias value (R5)

    // Output
    output wire [DATA_BITS-1:0] activation_out
);
    // SF16 constants (sign-magnitude: 0x8000 is negative zero)
    localparam [DATA_BITS-1:0] Q115_ZERO = 16'h0000;           // 0.0
    localparam [DATA_BITS-1:0] Q115_MAX = 16'h7FFF;            // +0.999969...
    localparam [DATA_BITS-1:0] Q115_MIN = 16'hFFFF;  // -0.999969... (most negative SF16: sign=1, mantissa=0x7FFF)
    localparam [DATA_BITS-1:0] Q115_LEAKY_ALPHA = 16'h0148;    // ~0.01 in SF16

    // Activation function codes
    localparam [1:0] ACT_NONE = 2'b00;
    localparam [1:0] ACT_RELU = 2'b01;
    localparam [1:0] ACT_LEAKY_RELU = 2'b10;
    localparam [1:0] ACT_CLIPPED_RELU = 2'b11;

    // Output register
    reg [DATA_BITS-1:0] activation_out_reg;
    assign activation_out = activation_out_reg;

    // ============================================
    // Stage 1: Bias Addition with Saturation (SF16 sign-magnitude)
    // ============================================
    // Extract sign and magnitude from SF16 inputs
    wire S_A = unbiased_activation[15];
    wire [14:0] M_A = unbiased_activation[14:0];
    wire S_B = bias[15];
    wire [14:0] M_B = bias[14:0];

    // Compute arithmetic options in parallel (single carry-propagate level)
    wire [15:0] sum_M = M_A + M_B;
    wire [15:0] diff_A_B = M_A - M_B;
    wire [15:0] diff_B_A = M_B - M_A;

    // Fast decision logic
    wire signs_equal = (S_A == S_B);
    wire A_gte_B = (M_A >= M_B);

    // Mux final sign and magnitude
    wire res_S = signs_equal ? S_A : (A_gte_B ? S_A : S_B);
    wire [14:0] res_M = signs_equal ? 
                        ((sum_M > 15'd32767) ? 15'd32767 : sum_M[14:0]) : 
                        (A_gte_B ? diff_A_B[14:0] : diff_B_A[14:0]);

    // Construct final sign-magnitude value and canonicalize negative zero
    wire [DATA_BITS-1:0] biased_activation = (res_M == 15'b0) ? {DATA_BITS{1'b0}} : {res_S, res_M};

    // ============================================
    // Stage 2: Activation Function
    // ============================================
    wire is_negative = biased_activation[15];  // Sign bit indicates negative (SF16 sign-magnitude)

    // Leaky ReLU: x * 0.01 for negative values
    // In SF16 sign-magnitude: just right-shift the mantissa (keeps sign bit)
    // mantissa >> 7 ≈ x * 0.0078 (close to 0.01)
    wire [14:0] leaky_mantissa = biased_activation[14:0] >> 7;
    wire [DATA_BITS-1:0] leaky_value = (leaky_mantissa == 15'b0) ? Q115_ZERO :
                                        {1'b1, leaky_mantissa};  // negative with reduced magnitude

    // Activation function selection — wire ternary for synthesis efficiency.
    // Yosys maps this to a 2-level mux tree and can share biased_activation/is_negative.
    wire [DATA_BITS-1:0] relu_out      = is_negative ? Q115_ZERO : biased_activation;
    wire [DATA_BITS-1:0] leaky_out     = is_negative ? leaky_value : biased_activation;
    wire [DATA_BITS-1:0] activated_value =
        (activation_func == ACT_RELU)        ? relu_out      :
        (activation_func == ACT_LEAKY_RELU)  ? leaky_out     :
        (activation_func == ACT_CLIPPED_RELU)? relu_out      : // same as ReLU (max already ≤1 in SF16)
                                               biased_activation; // ACT_NONE pass-through

    // ============================================
    // Pipeline control
    // ============================================
    always @(posedge clk) begin
        if (reset) begin
            activation_out_reg <= {DATA_BITS{1'b0}};
        end else if (enable) begin
            // Compute activation when in EXECUTE state
            if (core_state == 3'b101 && activation_enable) begin
                activation_out_reg <= activated_value;
            end
        end
    end
endmodule
