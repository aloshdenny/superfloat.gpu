`default_nettype none
`timescale 1ns/1ns

// BIAS & ACTIVATION (BA) UNIT (Q1.15 Fixed-Point)
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
    parameter DATA_BITS = 16  // Q1.15 fixed-point width
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
    // Q1.15 constants
    localparam [DATA_BITS-1:0] Q115_ZERO = 16'h0000;           // 0.0
    localparam [DATA_BITS-1:0] Q115_MAX = 16'h7FFF;            // +0.99997
    localparam [DATA_BITS-1:0] Q115_MIN = 16'h8000;            // -1.0
    localparam [DATA_BITS-1:0] Q115_LEAKY_ALPHA = 16'h0148;    // ~0.01 in Q1.15

    // Activation function codes
    localparam [1:0] ACT_NONE = 2'b00;
    localparam [1:0] ACT_RELU = 2'b01;
    localparam [1:0] ACT_LEAKY_RELU = 2'b10;
    localparam [1:0] ACT_CLIPPED_RELU = 2'b11;

    // Output register
    reg [DATA_BITS-1:0] activation_out_reg;
    assign activation_out = activation_out_reg;

    // ============================================
    // Stage 1: Bias Addition with Saturation
    // ============================================
    // Use the current bias input directly (the core FSM already holds operands stable
    // across the multi-cycle instruction execution). This avoids stale-bias issues
    // if REQUEST/EXECUTE phasing shifts by a cycle.
    wire signed [16:0] biased_sum = $signed({unbiased_activation[15], unbiased_activation}) + 
                                    $signed({bias[15], bias});

    // Saturation for bias addition
    wire overflow_pos = ~biased_sum[16] & biased_sum[15] & 
                        ~unbiased_activation[15] & ~bias[15];
    wire overflow_neg = biased_sum[16] & ~biased_sum[15] & 
                        unbiased_activation[15] & bias[15];
    
    wire [DATA_BITS-1:0] biased_activation = overflow_pos ? Q115_MAX :
                                              overflow_neg ? Q115_MIN :
                                              biased_sum[DATA_BITS-1:0];

    // ============================================
    // Stage 2: Activation Function
    // ============================================
    wire is_negative = biased_activation[15];  // Sign bit indicates negative

    // Leaky ReLU: x * 0.01 for negative values
    // Approximate by shift: x >> 7 ≈ x * 0.0078 (close to 0.01)
    wire signed [DATA_BITS-1:0] leaky_value = $signed(biased_activation) >>> 7;

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
                // In Q1.15, max is already ~1.0 (0x7FFF)
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
