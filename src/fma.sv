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
    // Convert SF16 sign-magnitude to signed integer (mantissa with sign)
    wire signed [15:0] r4_signed = rq[15] ? -$signed({1'b0, rq[14:0]}) :
                                            $signed({1'b0, rq[14:0]});
    wire signed [15:0] r3_signed = r3_weighted[15] ? -$signed({1'b0, r3_weighted[14:0]}) :
                                                     $signed({1'b0, r3_weighted[14:0]});

    // Add with overflow detection
    wire signed [16:0] acc_sum_ext = {r4_signed[15], r4_signed} + {r3_signed[15], r3_signed};

    // Saturate to ±32767 (no -32768 in SF16, no -1.0)
    wire signed [15:0] acc_sum_sat = (acc_sum_ext > 32767)  ? 16'sd32767 :
                                     (acc_sum_ext < -32767) ? -16'sd32767 :
                                     acc_sum_ext[15:0];

    // Convert signed result back to SF16 sign-magnitude
    wire [15:0] abs_acc_sum_sat = -acc_sum_sat;
    wire [DATA_BITS-1:0] acc_sm = (acc_sum_sat < 0) ? {1'b1, abs_acc_sum_sat[14:0]} :
                                                       {1'b0, acc_sum_sat[14:0]};
    // Canonicalize negative zero
    wire [DATA_BITS-1:0] accumulated_saturated = (acc_sm == NEG_ZERO) ? {DATA_BITS{1'b0}} : acc_sm;

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
