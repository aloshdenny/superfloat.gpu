`default_nettype none
`timescale 1ns/1ns

// OPTIMIZED FUSED MULTIPLY-ADD UNIT (SF16 Fixed-Point, Sign-Magnitude)
// 2-cycle pipelined MAC matched to the core scheduler:
// - REQUEST: latch rs/rt/rq into R1/R2/R4
// - EXECUTE cycle 0: compute (rs * rt) >> 15 with SF16 saturation, latch into R3
// - EXECUTE cycle 1: compute rq + R3 with SF16 saturation, latch to output
//
// SF16: x = (-1)^s · m / 2^15,  m ∈ {0, 1, ..., 2^15 - 1}
// SF16 × SF16 = SF31 (1 sign bit + 30 mantissa bits)
// Negative zero (0x8000) is canonicalized to 0x0000.
module fma #(
    parameter DATA_BITS = 16  // SF16 fixed-point width
) (
    input wire clk,
    input wire reset,
    input wire enable,

    input reg [2:0] core_state,
    input reg decoded_fma_enable,

    // SF16 inputs
    input wire [DATA_BITS-1:0] rs,    // Input/Activation (i)
    input wire [DATA_BITS-1:0] rt,    // Weight (j)
    input wire [DATA_BITS-1:0] rq,    // Previous accumulator value
    
    output wire [DATA_BITS-1:0] fma_out
);
    // SF16 saturation constants (sign-magnitude: 0x8000 is negative zero, not -1.0)
    localparam [DATA_BITS-1:0] Q115_MAX = 16'h7FFF;  // +0.999969...
    localparam [DATA_BITS-1:0] Q115_MIN = 16'hFFFF;  // -0.999969... (most negative SF16: sign=1, mantissa=0x7FFF)
    localparam [DATA_BITS-1:0] NEG_ZERO = 16'h8000;  // negative zero → must canonicalize to 0x0000
    localparam signed [31:0] Q115_MAX_S32 = 32'sd32767;
    localparam signed [31:0] Q115_MIN_S32 = -32'sd32767;  // symmetric range (no -1.0 in SF16)

    // Pipeline register (R3 from diagram) and output register
    reg [DATA_BITS-1:0] r3_weighted;      // R3: Weighted input (product, SF16)
    reg [DATA_BITS-1:0] fma_out_reg;
    assign fma_out = fma_out_reg;

    // ============================================
    // Multiply (SF16 sign-magnitude) with saturation
    // SF16 × SF16 = SF31 (1 sign + 30 mantissa bits)
    // Matches fma.sv approach: sign XOR + unsigned mantissa multiply
    // ============================================
    // Extract sign and magnitude from SF16 inputs
    wire sign_r1 = rs[15];
    wire sign_r2 = rt[15];
    wire sign_product = sign_r1 ^ sign_r2;
    wire [14:0] mag_r1 = rs[14:0];
    wire [14:0] mag_r2 = rt[14:0];

    // 15×15 unsigned multiply → 30-bit SF31 mantissa
    wire [29:0] product_unsigned = mag_r1 * mag_r2;

    // Shift right 15 to get SF16 mantissa
    wire [14:0] product_mag = product_unsigned[29:15];

    // Reconstruct SF16 product (sign-magnitude)
    wire [DATA_BITS-1:0] product_sm = {sign_product, product_mag};
    // Canonicalize: if mantissa is 0 and sign is 1, force to +0
    wire [DATA_BITS-1:0] product_saturated = (product_mag == 15'b0) ? {DATA_BITS{1'b0}} : product_sm;

    // ============================================
    // Accumulate (SF16 sign-magnitude) with saturation
    // Convert to signed for addition, then back to sign-magnitude
    // ============================================
    // Extract sign and magnitude from SF16 inputs
    wire S_A = rq[15];
    wire [14:0] M_A = rq[14:0];
    wire S_B = r3_weighted[15];
    wire [14:0] M_B = r3_weighted[14:0];

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
    wire [DATA_BITS-1:0] accumulated_saturated = (res_M == 15'b0) ? {DATA_BITS{1'b0}} : {res_S, res_M};

    // ============================================
    // Pipeline control
    // ============================================
    reg exec_phase;  // 0=mul stage, 1=acc stage (one FMA instruction spans 2 EXECUTE cycles)

    always @(posedge clk) begin
        if (reset) begin
            r3_weighted <= {DATA_BITS{1'b0}};
            fma_out_reg <= {DATA_BITS{1'b0}};
            exec_phase <= 1'b0;
        end else if (enable) begin
            if (core_state != 3'b101 || !decoded_fma_enable) begin
                exec_phase <= 1'b0;
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
