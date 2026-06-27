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
    // Convert SF16 sign-magnitude to signed integer
    wire signed [15:0] act_signed = unbiased_activation[15] ? -$signed({1'b0, unbiased_activation[14:0]}) :
                                                              $signed({1'b0, unbiased_activation[14:0]});
    wire signed [15:0] bias_signed = bias[15] ? -$signed({1'b0, bias[14:0]}) :
                                                 $signed({1'b0, bias[14:0]});

    // Add with overflow detection
    wire signed [16:0] biased_sum_ext = {act_signed[15], act_signed} + {bias_signed[15], bias_signed};

    // Saturate to ±32767 (symmetric SF16 range)
    wire signed [15:0] biased_sum_sat = (biased_sum_ext > 32767)  ? 16'sd32767 :
                                        (biased_sum_ext < -32767) ? -16'sd32767 :
                                        biased_sum_ext[15:0];

    // Convert back to SF16 sign-magnitude
    wire [15:0] abs_biased_sum_sat = -biased_sum_sat;
    wire [DATA_BITS-1:0] biased_sm = (biased_sum_sat < 0) ? {1'b1, abs_biased_sum_sat[14:0]} :
                                                              {1'b0, biased_sum_sat[14:0]};
    // Canonicalize negative zero
    wire [DATA_BITS-1:0] biased_activation = (biased_sm == 16'h8000) ? 16'h0000 : biased_sm;

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

    // Activation function selection
    reg [DATA_BITS-1:0] activated_value;
    
    always @(*) begin
        case (activation_func)
            ACT_NONE: begin
                // Pass-through: no activation
                activated_value = biased_activation;
            end
            ACT_RELU: begin
                // ReLU: max(0, x)
                activated_value = is_negative ? Q115_ZERO : biased_activation;
            end
            ACT_LEAKY_RELU: begin
                // Leaky ReLU: x if x > 0, else ~0.01*x
                activated_value = is_negative ? leaky_value : biased_activation;
            end
            ACT_CLIPPED_RELU: begin
                // Clipped ReLU: min(max_val, max(0, x))
                // In SF16, max is already ~1.0 (0x7FFF)
                activated_value = is_negative ? Q115_ZERO : biased_activation;
            end
            default: begin
                activated_value = biased_activation;
            end
        endcase
    end

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
