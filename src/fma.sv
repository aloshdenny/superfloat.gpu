`default_nettype none
`timescale 1ns/1ns

// OPTIMIZED FUSED MULTIPLY-ADD UNIT (Q1.15 Fixed-Point)
// Following the FMA Unit diagram architecture:
// - R1: Input/Activation register (16-bit)
// - R2: Weight register (16-bit)  
// - R3: Weighted input register (16-bit) with sign from XOR
// - R4: Accumulated sum register (16-bit)
// - Sign handling via XOR of sign bits
// - 15-bit x 15-bit mantissa multiplication (smaller multiplier)
// - Pipeline registers for better timing
module fma #(
    parameter DATA_BITS = 16  // Q1.15 fixed-point width
) (
    input wire clk,
    input wire reset,
    input wire enable,

    input reg [2:0] core_state,
    input reg decoded_fma_enable,

    // Q1.15 inputs
    input wire [DATA_BITS-1:0] rs,    // Input/Activation (i)
    input wire [DATA_BITS-1:0] rt,    // Weight (j)
    input wire [DATA_BITS-1:0] rq,    // Previous accumulator value
    
    output wire [DATA_BITS-1:0] fma_out
);
    // Q1.15 saturation constants
    localparam [DATA_BITS-1:0] Q115_MAX = 16'h7FFF;  // +0.99997
    localparam [DATA_BITS-1:0] Q115_MIN = 16'h8000;  // -1.0

    // Pipeline registers (R1-R4 from diagram)
    reg [DATA_BITS-1:0] r1_activation;    // R1: Input/Activation
    reg [DATA_BITS-1:0] r2_weight;        // R2: Weight
    reg [DATA_BITS-1:0] r3_weighted;      // R3: Weighted input (product with sign)
    reg [DATA_BITS-1:0] r4_accumulated;   // R4: Accumulated sum

    // Output register
    reg [DATA_BITS-1:0] fma_out_reg;
    assign fma_out = fma_out_reg;

    // ============================================
    // Stage 1: Sign bit extraction and XOR
    // ============================================
    wire sign_r1 = r1_activation[15];         // Sign bit of activation
    wire sign_r2 = r2_weight[15];             // Sign bit of weight
    wire sign_product = sign_r1 ^ sign_r2;    // XOR for result sign

    // ============================================
    // Stage 2: 15-bit mantissa extraction
    // ============================================
    // For Q1.15: bit 15 is sign, bits 14:0 are the magnitude/mantissa
    // We use absolute values for unsigned multiplication
    wire [14:0] mantissa_r1 = sign_r1 ? (~r1_activation[14:0] + 1'b1) : r1_activation[14:0];
    wire [14:0] mantissa_r2 = sign_r2 ? (~r2_weight[14:0] + 1'b1) : r2_weight[14:0];

    // ============================================
    // Stage 3: 15x15 unsigned multiplication
    // ============================================
    // 15-bit x 15-bit = 30-bit result
    // This is smaller than full 16x16 signed multiply
    wire [29:0] product_unsigned = mantissa_r1 * mantissa_r2;

    // ============================================
    // Stage 4: Extract Q1.15 result and apply sign
    // ============================================
    // Q1.15 * Q1.15 = Q2.30, shift right 15 to get Q1.15
    wire [14:0] product_mantissa = product_unsigned[29:15];
    
    // Reconstruct signed Q1.15 weighted input
    wire [DATA_BITS-1:0] weighted_input_unsigned = {1'b0, product_mantissa};
    wire [DATA_BITS-1:0] weighted_input = sign_product ? 
                                          (~weighted_input_unsigned + 1'b1) : 
                                          weighted_input_unsigned;

    // ============================================
    // Stage 5: Accumulation with saturation
    // ============================================
    wire signed [16:0] acc_sum = $signed({r3_weighted[15], r3_weighted}) + 
                                  $signed({r4_accumulated[15], r4_accumulated});

    // Saturation logic
    wire overflow_pos = ~acc_sum[16] & acc_sum[15] & ~r3_weighted[15] & ~r4_accumulated[15];
    wire overflow_neg = acc_sum[16] & ~acc_sum[15] & r3_weighted[15] & r4_accumulated[15];
    
    wire [DATA_BITS-1:0] accumulated_saturated = overflow_pos ? Q115_MAX :
                                                  overflow_neg ? Q115_MIN :
                                                  acc_sum[DATA_BITS-1:0];

    // ============================================
    // Pipeline control
    // ============================================
    always @(posedge clk) begin
        if (reset) begin
            r1_activation <= {DATA_BITS{1'b0}};
            r2_weight <= {DATA_BITS{1'b0}};
            r3_weighted <= {DATA_BITS{1'b0}};
            r4_accumulated <= {DATA_BITS{1'b0}};
            fma_out_reg <= {DATA_BITS{1'b0}};
        end else if (enable) begin
            // Load inputs when in REQUEST state
            if (core_state == 3'b011) begin
                r1_activation <= rs;          // Load activation
                r2_weight <= rt;              // Load weight
                r4_accumulated <= rq;         // Load previous accumulator
            end
            
            // Execute when in EXECUTE state and FMA enabled
            if (core_state == 3'b101 && decoded_fma_enable) begin
                // Pipeline Stage: Multiply
                r3_weighted <= weighted_input;
                
                // Pipeline Stage: Accumulate
                fma_out_reg <= accumulated_saturated;
            end
        end
    end
endmodule
