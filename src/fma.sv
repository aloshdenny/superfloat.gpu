`default_nettype none
`timescale 1ns/1ns

// OPTIMIZED FUSED MULTIPLY-ADD UNIT (Q1.15 Fixed-Point)
// 2-cycle pipelined MAC matched to the core scheduler:
// - REQUEST: latch rs/rt/rq into R1/R2/R4
// - EXECUTE cycle 0: compute (rs * rt) >> 15 with Q1.15 saturation, latch into R3
// - EXECUTE cycle 1: compute rq + R3 with Q1.15 saturation, latch to output
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
    localparam signed [31:0] Q115_MAX_S32 = 32'sd32767;
    localparam signed [31:0] Q115_MIN_S32 = -32'sd32768;

    // Pipeline registers (R1-R4 from diagram)
    reg [DATA_BITS-1:0] r1_activation;    // R1: Input/Activation
    reg [DATA_BITS-1:0] r2_weight;        // R2: Weight
    reg [DATA_BITS-1:0] r3_weighted;      // R3: Weighted input (product, Q1.15)
    reg [DATA_BITS-1:0] r4_accumulated;   // R4: Accumulated sum

    // Output register
    reg [DATA_BITS-1:0] fma_out_reg;
    assign fma_out = fma_out_reg;

    // ============================================
    // Multiply (Q1.15) with saturation (matches test/helpers/q115.py:q115_mul)
    // ============================================
    wire signed [31:0] product_full_s32 = $signed(r1_activation) * $signed(r2_weight); // Q2.30
    wire signed [31:0] product_q115_s32 = product_full_s32 >>> 15;                     // Q1.15
    wire [DATA_BITS-1:0] product_saturated = (product_q115_s32 > Q115_MAX_S32) ? Q115_MAX :
                                             (product_q115_s32 < Q115_MIN_S32) ? Q115_MIN :
                                             product_q115_s32[DATA_BITS-1:0];

    // ============================================
    // Accumulate (Q1.15) with saturation (matches test/helpers/q115.py:q115_add)
    // ============================================
    wire signed [31:0] acc_sum_s32 = $signed(r4_accumulated) + $signed(r3_weighted);
    wire [DATA_BITS-1:0] accumulated_saturated = (acc_sum_s32 > Q115_MAX_S32) ? Q115_MAX :
                                                 (acc_sum_s32 < Q115_MIN_S32) ? Q115_MIN :
                                                 acc_sum_s32[DATA_BITS-1:0];

    // ============================================
    // Pipeline control
    // ============================================
    reg exec_phase;  // 0=mul stage, 1=acc stage (one FMA instruction spans 2 EXECUTE cycles)

    always @(posedge clk) begin
        if (reset) begin
            r1_activation <= {DATA_BITS{1'b0}};
            r2_weight <= {DATA_BITS{1'b0}};
            r3_weighted <= {DATA_BITS{1'b0}};
            r4_accumulated <= {DATA_BITS{1'b0}};
            fma_out_reg <= {DATA_BITS{1'b0}};
            exec_phase <= 1'b0;
        end else if (enable) begin
            if (core_state != 3'b101 || !decoded_fma_enable) begin
                exec_phase <= 1'b0;
            end

            // Load inputs when in REQUEST state
            if (core_state == 3'b011) begin
                r1_activation <= rs;          // Load activation
                r2_weight <= rt;              // Load weight
                r4_accumulated <= rq;         // Load previous accumulator
            end
            
            // Execute when in EXECUTE state and FMA enabled
            if (core_state == 3'b101 && decoded_fma_enable) begin
                if (!exec_phase) begin
                    // EXECUTE cycle 0: multiply stage
                    r3_weighted <= product_saturated;
                    exec_phase <= 1'b1;
                end else begin
                    // EXECUTE cycle 1: accumulate stage
                    fma_out_reg <= accumulated_saturated;
                    exec_phase <= 1'b0;
                end
            end
        end
    end
endmodule
