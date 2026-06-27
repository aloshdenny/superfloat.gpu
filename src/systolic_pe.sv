// =============================================================================
// SYSTOLIC FMA — SF16 × SF16 → SF16 (3-stage FMA pipeline)
// Target: Sky130 HD @ 100 MHz (10 ns period)  ← achievable with 15×15 mult
//
// SF16 format: x = (-1)^s · m / 2^15,  m ∈ [0, 2^15-1]
//   bit[15]   = sign
//   bits[14:0] = 15-bit unsigned mantissa
//   0x8000    = negative zero → canonicalised to 0x0000 on input
//
// Pipeline (matches FMA diagram exactly):
//   Cycle 1 → Stage 0 : R1 (activation reg) + R2 (weight stationary reg)
//                        → sign_a, mantissa_a, sign_w, mantissa_w registered
//   Cycle 2 → Stage 1 : mantissa_a × mantissa_w (15×15 unsigned)
//                        → XOR signs, form R3 (signed 16-bit two's-complement)
//   Cycle 3 → Stage 2 : R3 + R4 (accumulator) with saturation → R4
//
// Latency : first result in R4 after 3 cycles from input presentation
// Throughput : 1 MAC / cycle (fully pipelined)
//
// Negative-zero (0x8000) is canonicalised to 0x0000 at both the activation
// input and the weight load path, so no negative-zero ever propagates.
//
// Two's-complement accumulator (R4): internally we keep the running sum in
// 16-bit signed two's complement to make the adder trivial.  The acc_out
// output converts back to SF16 sign-magnitude on the fly (combinational,
// ~2 gates — not on any critical path).
//
// Critical path (setup-limited):
//   mantissa_a_r × mantissa_w_r   ← 15×15 unsigned multiply
//   → 30-bit product
//   → product[29:15] (top 15 bits = Q1.15 result)
//   → conditional 2's-complement negate (1 adder, 16-bit)
//   → register into R3
//   ALL of the above must fit inside 1 clock period (Stage 1 reg-to-reg).
//   At 10 ns / Sky130 HD:  15×15 Booth ≈ 4–5 ns, negate ≈ 1 ns → ~6 ns.
//   Slack margin ~4 ns before routing; should close cleanly.
//
// =============================================================================
`default_nettype none
`timescale 1ns / 1ps

module systolic_pe #(
    parameter DATA_BITS = 16
) (
    input  wire                  clk,
    input  wire                  reset,
    input  wire                  enable,

    // ---- control ----
    input  wire                  clear_acc,      // synchronous accumulator clear
    input  wire                  load_weight,    // latch b_in as stationary weight
    input  wire                  compute_enable, // gate multiply-accumulate

    // ---- data (west→east, north→south) ----
    input  wire [DATA_BITS-1:0]  a_in,
    input  wire [DATA_BITS-1:0]  b_in,

    output reg  [DATA_BITS-1:0]  a_out,
    output reg  [DATA_BITS-1:0]  b_out,

    // acc_out: SF16 sign-magnitude view of accumulator (combinational)
    output wire [DATA_BITS-1:0]  acc_out
);

// ---------------------------------------------------------------------------
// 0. Input canonicalisation (combinational, before any register)
// ---------------------------------------------------------------------------
// Negative-zero → zero.  This is pure wiring / a mux, no timing cost.
wire [DATA_BITS-1:0] a_canon = (a_in == 16'h8000) ? 16'h0000 : a_in;
wire [DATA_BITS-1:0] b_canon = (b_in == 16'h8000) ? 16'h0000 : b_in;

// ---------------------------------------------------------------------------
// STAGE 0 REGISTERS (R1, R2)
//   R1: registered activation → a_out (also forwarded east)
//   R2: stationary weight register (loaded when load_weight is asserted)
//   We also register the pipeline valid bit here.
// ---------------------------------------------------------------------------
// R1 — activation pass-through (also feeds Stage 1 multiply)
// (a_out IS R1 in the diagram)

// R2 — stationary weight (sign + mantissa stored separately to expose
//       sign clearly for XOR in Stage 1 without an extra mux level)
reg         r2_sign;
reg  [14:0] r2_mantissa;

// Stage-0 valid: did compute_enable arrive this cycle?
reg  valid_s0;

// ---------------------------------------------------------------------------
// STAGE 1 REGISTERS (R3)
//   Unsigned product mantissa and product sign
// ---------------------------------------------------------------------------
reg  [14:0] r3_prod_mant;  // R3 mantissa in diagram
reg         r3_prod_sign;  // R3 sign in diagram
reg               valid_s1;

// ---------------------------------------------------------------------------
// STAGE 2 REGISTER (R4) — accumulator
// ---------------------------------------------------------------------------
reg signed [15:0] r4_acc;      // R4 in diagram

// ---------------------------------------------------------------------------
// Stage 1 combinational logic
//   Inputs: a_out (= R1), r2_sign/r2_mantissa (= R2)
//   Outputs: feeds R3 register next cycle
//
// IMPORTANT: we compute off the *registered* a_out and r2_* so the
// multiply path is purely reg-to-reg (no input-pin combinational path
// feeding directly into the multiply).
// ---------------------------------------------------------------------------
wire        s1_sign_a       = a_out[15];          // R1 sign
wire [14:0] s1_mant_a       = a_out[14:0];        // R1 mantissa

// 15×15 unsigned product -> 30-bit
wire [29:0] s1_prod_wide = s1_mant_a * r2_mantissa;

// Q1.15 rounding: take upper 15 bits (bits [29:15])
wire [14:0] s1_prod_mant    = s1_prod_wide[29:15];

// XOR signs to get product sign
wire        s1_sign_prod    = s1_sign_a ^ r2_sign;

// ---------------------------------------------------------------------------
// Stage 2 combinational logic
//   Inputs: r3_prod_mant, r3_prod_sign (R3), r4_acc (R4)
//   Output: saturated sum → feeds R4 register
// ---------------------------------------------------------------------------
// Extend operands to 17 bits signed
wire signed [16:0] s2_acc_ext  = {r4_acc[15], r4_acc};
wire signed [16:0] s2_prod_ext = {2'b0, r3_prod_mant}; // positive absolute value

// If negative sign, subtract; otherwise, add
wire signed [16:0] s2_sum_wide =
    r3_prod_sign ? (s2_acc_ext - s2_prod_ext) : (s2_acc_ext + s2_prod_ext);

// Overflow when sign of result != both operands' signs (and they matched)
// Simplified: overflow iff extended bit != sign bit of lower 16 bits
wire s2_overflow = (s2_sum_wide[16] != s2_sum_wide[15]);

// Negative-zero guard on 0x8000: map to 0x8001 (MIN) regardless
wire s2_neg_zero = (s2_sum_wide[15:0] == 16'h8000);

localparam signed [15:0] SAT_MAX = 16'sh7FFF;
localparam signed [15:0] SAT_MIN = 16'sh8001;

wire signed [15:0] s2_sat =
    (s2_overflow || s2_neg_zero) ?
        (s2_sum_wide[16] ? SAT_MIN : SAT_MAX) :
        s2_sum_wide[15:0];

// ---------------------------------------------------------------------------
// acc_out: sign-magnitude SF16 view of R4 (combinational readout)
// The negation is only ~4 gates; not on any timing-critical path.
// ---------------------------------------------------------------------------
wire [14:0] acc_abs = r4_acc[15] ? 15'(-r4_acc[15:0]) : r4_acc[14:0];
assign acc_out = {r4_acc[15], acc_abs};

// ---------------------------------------------------------------------------
// Sequential block
// ---------------------------------------------------------------------------
always @(posedge clk) begin
    if (reset) begin
        // All pipeline registers → 0
        a_out        <= {DATA_BITS{1'b0}};
        b_out        <= {DATA_BITS{1'b0}};
        r2_sign      <= 1'b0;
        r2_mantissa  <= 15'b0;
        r3_prod_mant <= 15'b0;
        r3_prod_sign <= 1'b0;
        r4_acc       <= 16'sb0;
        valid_s0     <= 1'b0;
        valid_s1     <= 1'b0;
    end else if (enable) begin

        // --- East/south pass-throughs (1-cycle delay) ---
        a_out <= a_canon;   // R1: registered activation
        b_out <= b_canon;   // weight fanout (south)

        // --- R2: stationary weight load ---
        if (load_weight) begin
            r2_sign     <= b_canon[15];
            r2_mantissa <= b_canon[14:0];
        end

        // --- Clear path (synchronous, priority over compute) ---
        if (clear_acc) begin
            r3_prod_mant <= 15'b0;
            r3_prod_sign <= 1'b0;
            r4_acc       <= 16'sb0;
            valid_s0     <= 1'b0;
            valid_s1     <= 1'b0;
        end else begin
            // --- Stage 0→1 valid propagation ---
            valid_s0 <= compute_enable;
            valid_s1 <= valid_s0;

            // --- Stage 1: register product into R3 ---
            // (always latch so the register holds the last computed value;
            //  valid_s1 gates whether R4 consumes it)
            r3_prod_mant <= s1_prod_mant;
            r3_prod_sign <= s1_sign_prod;

            // --- Stage 2: accumulate R3 into R4 ---
            if (valid_s1) begin
                r4_acc <= s2_sat;
            end
        end
    end
end

endmodule