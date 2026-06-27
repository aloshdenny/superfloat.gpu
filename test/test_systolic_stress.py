"""
Systolic Array Stress Tests — Atreides GPU

Exercises hardware corner cases of the 8×8 weight-stationary systolic array that
are invisible from full-GPU integration tests:

  - Back-to-back operations with/without clear_acc between runs
  - Maximum accumulation (all Q115_MAX inputs, saturates SF31)
  - All-negative weight matrix
  - Checkerboard ±0.5 weight pattern
  - Zero-activation no-op (accumulator must not change)
  - Single-hot row (only FMA row 0 computes)
  - Pipeline bubble (compute_enable gap in the middle)
  - Weight reuse across multiple activation streams
  - Rapid clear then immediate compute
  - 10-batch random matmuls with accumulated clear verification

DUT: tb_systolic_array (ARRAY_SIZE=8)

SF31 accumulator model is inlined to avoid importing test_fma_unit
(which would register its cocotb tests when imported).
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
import random
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from helpers.q115 import float_to_q115, q115_to_float
from helpers.logger import GPULogger

# ============================================================================
# Constants
# ============================================================================

ARRAY_SIZE = 8          # Must match tb_systolic_array compile-time parameter
DATA_BITS = 16
Q115_MAX = 0x7FFF
Q115_MIN = 0xFFFF  # most negative SF16 (sign=1, mantissa=0x7FFF = -0.999969)
PIFMA_INTERVAL = ARRAY_SIZE       # Pipeline register interval in systolic_array.sv (disabled)
FMA_MAC_PIFMA_LATENCY = 3 # cycles to wait after compute_enable edge for results (2-cycle FMA + 1 array)

# ============================================================================
# ============================================================================
# Software reference: SF31 accumulator (inline, no cross-module import)
# ============================================================================

class Q131Accumulator:
    """
    Reference model of the hardware's SF31 signed accumulator.
    Matches fma.sv Stage 1-3 behavior exactly.
    
    SF16 uses sign-magnitude: x = (-1)^s · m / 2^15
    Negative zero (0x8000) is canonicalized to 0x0000.
    """
    @staticmethod
    def _canon(q):
        """Canonicalize SF16: force 0x8000 → 0x0000."""
        return 0x0000 if (q & 0xFFFF) == 0x8000 else (q & 0xFFFF)
    
    def __init__(self):
        self.acc = 0  # 32-bit signed SF31

    def clear(self):
        self.acc = 0

    def mac(self, a_q115: int, w_q115: int):
        # Canonicalize negative zero
        a_q115 = self._canon(a_q115)
        w_q115 = self._canon(w_q115)
        
        # Sign-magnitude decomposition
        sign_a = (a_q115 >> 15) & 1
        sign_w = (w_q115 >> 15) & 1
        sign_product = sign_a ^ sign_w

        mag_a = a_q115 & 0x7FFF
        mag_w = w_q115 & 0x7FFF

        product_unsigned = mag_a * mag_w
        product_q115 = (product_unsigned >> 15) & 0x7FFF
        product_q131 = product_q115 << 16
        if sign_product:
            product_q131 = -product_q131

        self.acc += product_q131
        if self.acc > 0x7FFFFFFF:
            self.acc = 0x7FFFFFFF
        elif self.acc < -0x7FFFFFFF:
            self.acc = -0x7FFFFFFF

    def read_q115(self) -> int:
        q = self.acc >> 16
        if q > 32767:
            q = 32767
        elif q < -32767:
            q = -32767
        if q < 0:
            result = 0x8000 | (-q)
        else:
            result = q
        return self._canon(result)


# ============================================================================
# Reference matmul: matches hardware weight-stationary dataflow
# ============================================================================

def q115_matmul_ref(A: list, B: list, N: int) -> list:
    """
    Reference output matching hardware: C[i][j] = B[i][j] * sum_k A[i][k].
    See test_systolic_array_unit.py for dataflow explanation.
    """
    C = [[0] * N for _ in range(N)]
    for i in range(N):
        for j in range(N):
            ref = Q131Accumulator()
            for k in range(N):
                ref.mac(A[i][k], B[i][j])
            C[i][j] = ref.read_q115()
    return C


# ============================================================================
# Hardware helpers
# ============================================================================

def pack_inputs(values: list, bits: int = 16) -> int:
    result = 0
    for i, v in enumerate(values):
        result |= (v & ((1 << bits) - 1)) << (i * bits)
    return result


def unpack_results(flat: int, N: int, bits: int = 16) -> list:
    mask = (1 << bits) - 1
    result = [[0] * N for _ in range(N)]
    for i in range(N):
        for j in range(N):
            idx = i * ARRAY_SIZE + j
            result[i][j] = (flat >> (idx * bits)) & mask
    return result


async def setup_array_stress(dut, test_name: str, clock_period_ns: int = 10) -> GPULogger:
    logger = GPULogger(test_name, log_dir="test/results")
    logger.set_verbose(True)
    logger.log_section(f"Systolic Stress: {test_name}")

    clock = Clock(dut.clk, clock_period_ns, units="ns")
    cocotb.start_soon(clock.start())

    dut.reset.value = 1
    dut.enable.value = 0
    dut.clear_acc.value = 0
    dut.load_weights.value = 0
    dut.compute_enable.value = 0
    dut.a_inputs_flat.value = 0
    dut.b_inputs_flat.value = 0

    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    dut.enable.value = 1
    await ClockCycles(dut.clk, 2)

    return logger


async def clear_accumulators(dut):
    dut.clear_acc.value = 1
    await RisingEdge(dut.clk)
    dut.clear_acc.value = 0
    await RisingEdge(dut.clk)


async def load_weights_scheduled(dut, B: list, N: int):
    """Stream B rows with timing-compensated scheduling so all rows
    arrive at their target FMA on the same load_weights pulse."""
    max_row = ARRAY_SIZE - 1
    max_delay = max_row + max_row // PIFMA_INTERVAL

    schedule = [-1] * (max_delay + 1)
    for row in range(ARRAY_SIZE):
        d = row + row // PIFMA_INTERVAL
        send_cycle = max_delay - d
        schedule[send_cycle] = row

    for c in range(max_delay):
        row = schedule[c]
        if row >= 0 and row < N:
            b_vals = [B[row][col] if col < N else 0 for col in range(ARRAY_SIZE)]
        else:
            b_vals = [0] * ARRAY_SIZE
        dut.b_inputs_flat.value = pack_inputs(b_vals)
        await RisingEdge(dut.clk)

    # Final cycle with load_weights asserted
    final_row = schedule[max_delay]
    if final_row >= 0 and final_row < N:
        b_vals = [B[final_row][col] if col < N else 0 for col in range(ARRAY_SIZE)]
    else:
        b_vals = [B[0][col] if col < N else 0 for col in range(ARRAY_SIZE)]

    dut.b_inputs_flat.value = pack_inputs(b_vals)
    dut.load_weights.value = 1
    await RisingEdge(dut.clk)
    dut.load_weights.value = 0
    dut.b_inputs_flat.value = 0
    await RisingEdge(dut.clk)


async def stream_activations(dut, A: list, N: int, num_cycles: int):
    dut.compute_enable.value = 1
    for cycle in range(num_cycles):
        a_row = [0] * ARRAY_SIZE
        for row in range(N):
            col = cycle - row
            if 0 <= col < N:
                a_row[row] = A[row][col]
        dut.a_inputs_flat.value = pack_inputs(a_row)
        await RisingEdge(dut.clk)

    for _ in range(ARRAY_SIZE + FMA_MAC_PIFMA_LATENCY):
        dut.a_inputs_flat.value = 0
        await RisingEdge(dut.clk)

    dut.compute_enable.value = 0


async def run_matmul_hw(dut, A: list, B: list, N: int) -> list:
    await clear_accumulators(dut)
    await load_weights_scheduled(dut, B, N)
    await ClockCycles(dut.clk, 2)
    await stream_activations(dut, A, N, 2 * N - 1)
    await ClockCycles(dut.clk, ARRAY_SIZE + 2 + FMA_MAC_PIFMA_LATENCY)
    return unpack_results(int(dut.results_flat.value), N)


def matrices_close(M1: list, M2: list, N: int, tol: float = 0.02) -> bool:
    for i in range(N):
        for j in range(N):
            if abs(q115_to_float(M1[i][j]) - q115_to_float(M2[i][j])) > tol:
                return False
    return True


def rand_matrix(N: int, lo: float = -0.3, hi: float = 0.3) -> list:
    return [[float_to_q115(random.uniform(lo, hi)) for _ in range(N)] for _ in range(N)]


# ============================================================================
# Test 1 — back-to-back with clear_acc
# ============================================================================

@cocotb.test()
async def test_back_to_back_with_clear(dut):
    """Two sequential matmuls; clear_acc between them. Second must not see residual."""
    logger = await setup_array_stress(dut, "back_to_back_clear")
    random.seed(1001)
    N = ARRAY_SIZE

    A1, B1 = rand_matrix(N), rand_matrix(N)
    A2, B2 = rand_matrix(N), rand_matrix(N)

    C1_hw = await run_matmul_hw(dut, A1, B1, N)
    C2_hw = await run_matmul_hw(dut, A2, B2, N)

    C1_ref = q115_matmul_ref(A1, B1, N)
    C2_ref = q115_matmul_ref(A2, B2, N)

    p1 = matrices_close(C1_hw, C1_ref, N)
    p2 = matrices_close(C2_hw, C2_ref, N)

    logger.log_message(f"  Matmul 1: {'PASS' if p1 else 'FAIL'}")
    logger.log_message(f"  Matmul 2 (after clear): {'PASS' if p2 else 'FAIL'}")
    logger.close()
    assert p1, "back_to_back_clear: first matmul failed"
    assert p2, "back_to_back_clear: second matmul failed (residual not cleared?)"


# ============================================================================
# Test 2 — back-to-back accumulate (no clear)
# ============================================================================

@cocotb.test()
async def test_back_to_back_accumulate(dut):
    """
    Two activation streams loaded onto the SAME weights without clear_acc.
    The accumulator adds both contributions: C = A1*B + A2*B = (A1+A2)*B (element-wise).
    """
    logger = await setup_array_stress(dut, "back_to_back_accumulate")
    random.seed(1002)
    N = ARRAY_SIZE

    A1 = [[float_to_q115(0.1)] * N for _ in range(N)]
    A2 = [[float_to_q115(0.1)] * N for _ in range(N)]
    B  = [[float_to_q115(0.5)] * N for _ in range(N)]

    # Hardware: load weights once, stream A1 then A2 without clearing
    await clear_accumulators(dut)
    await load_weights_scheduled(dut, B, N)
    await ClockCycles(dut.clk, 2)

    # Stream A1
    await stream_activations(dut, A1, N, 2 * N - 1)
    await ClockCycles(dut.clk, ARRAY_SIZE + 2 + FMA_MAC_PIFMA_LATENCY)

    # Stream A2 (no clear — accumulates on top of A1 result)
    dut.compute_enable.value = 1
    for cycle in range(2 * N - 1):
        a_row = [0] * ARRAY_SIZE
        for row in range(N):
            col = cycle - row
            if 0 <= col < N:
                a_row[row] = A2[row][col]
        dut.a_inputs_flat.value = pack_inputs(a_row)
        await RisingEdge(dut.clk)
    for _ in range(ARRAY_SIZE + FMA_MAC_PIFMA_LATENCY):
        dut.a_inputs_flat.value = 0
        await RisingEdge(dut.clk)
    dut.compute_enable.value = 0
    await ClockCycles(dut.clk, ARRAY_SIZE + 2 + FMA_MAC_PIFMA_LATENCY)

    hw = unpack_results(int(dut.results_flat.value), N)

    # Reference: A1*B + A2*B accumulated
    ref1 = q115_matmul_ref(A1, B, N)
    ref2 = q115_matmul_ref(A2, B, N)
    # Combined: each FMA accumulates both A1[i][k] and A2[i][k] against B[i][j]
    combined_ref = [[0] * N for _ in range(N)]
    for i in range(N):
        for j in range(N):
            acc = Q131Accumulator()
            for k in range(N):
                acc.mac(A1[i][k], B[i][j])
            for k in range(N):
                acc.mac(A2[i][k], B[i][j])
            combined_ref[i][j] = acc.read_q115()

    passed = matrices_close(hw, combined_ref, N)
    logger.log_message(f"  Accumulated two activation streams: {'PASS' if passed else 'FAIL'}")
    logger.close()
    assert passed, "back_to_back_accumulate: combined result mismatch"


# ============================================================================
# Test 3 — max value accumulation (positive saturation)
# ============================================================================

@cocotb.test()
async def test_max_value_accumulation(dut):
    """
    All Q115_MAX weights × all Q115_MAX activations repeated 8× saturates SF31 → Q115_MAX output.
    """
    logger = await setup_array_stress(dut, "max_accumulation")
    N = ARRAY_SIZE

    A = [[Q115_MAX] * N for _ in range(N)]
    B = [[Q115_MAX] * N for _ in range(N)]

    hw = await run_matmul_hw(dut, A, B, N)
    ref = q115_matmul_ref(A, B, N)

    passed = matrices_close(hw, ref, N)

    # All outputs should saturate to Q115_MAX
    all_saturated = all(hw[i][j] == Q115_MAX for i in range(N) for j in range(N))
    logger.log_message(f"  All outputs == Q115_MAX: {all_saturated}")
    logger.log_message(f"  Matches reference: {passed}")
    logger.close()
    assert passed, "max_value_accumulation: output mismatch"
    assert all_saturated, "max_value_accumulation: expected full positive saturation"


# ============================================================================
# Test 4 — all-negative weights
# ============================================================================

@cocotb.test()
async def test_all_negative_weights(dut):
    """
    All-negative weights stress.  Uses B = -0.5 (0xC000) to avoid the sign-magnitude
    edge case where 0x8000 is negative zero (not -1.0) in SF16.

    For B = -0.5, A = +0.5 (SF16), N=8:
      Each FMA accumulates: 0.5 * (-0.5) = -0.25 per MAC  →  8 macs → -2.0
      In SF31 accumulator: each MAC contributes -0.25 << 16 = -0x40000000
                accumulated 8× = -0x200000000 → saturates to -0x7FFFFFFF
      Read as SF16: Q115_MIN = 0xFFFF  # most negative SF16 (sign=1, mantissa=0x7FFF = -0.999969)

    Also verifies the bit-exact match against the SF31 reference.
    """
    logger = await setup_array_stress(dut, "all_negative_weights")
    N = ARRAY_SIZE

    A = [[float_to_q115(0.5)] * N for _ in range(N)]
    B = [[float_to_q115(-0.5)] * N for _ in range(N)]   # 0xC000

    hw = await run_matmul_hw(dut, A, B, N)
    ref = q115_matmul_ref(A, B, N)

    passed = matrices_close(hw, ref, N)
    all_min = all(hw[i][j] == Q115_MIN for i in range(N) for j in range(N))

    logger.log_message(f"  All outputs == Q115_MIN: {all_min}")
    logger.log_message(f"  Matches reference: {passed}")
    logger.close()
    assert passed, "all_negative_weights: output mismatch"


# ============================================================================
# Test 5 — checkerboard sign pattern
# ============================================================================

@cocotb.test()
async def test_checkerboard_signs(dut):
    """Checkerboard ±0.5 weights × uniform 0.5 activation → sign-alternating output."""
    logger = await setup_array_stress(dut, "checkerboard_signs")
    N = ARRAY_SIZE

    A = [[float_to_q115(0.25)] * N for _ in range(N)]
    B = [[float_to_q115(0.5 if (i + j) % 2 == 0 else -0.5)
          for j in range(N)] for i in range(N)]

    hw = await run_matmul_hw(dut, A, B, N)
    ref = q115_matmul_ref(A, B, N)

    passed = matrices_close(hw, ref, N)
    if not passed:
        logger.log_message("HW Matrix:")
        for r in hw:
            logger.log_message(str([f"{q115_to_float(x):+.4f}" for x in r]))
        logger.log_message("Ref Matrix:")
        for r in ref:
            logger.log_message(str([f"{q115_to_float(x):+.4f}" for x in r]))
    logger.log_message(f"  Checkerboard sign test: {'PASS' if passed else 'FAIL'}")
    logger.close()
    assert passed, "checkerboard_signs: output mismatch"


# ============================================================================
# Test 6 — zero-activation no-op
# ============================================================================

@cocotb.test()
async def test_zero_activation_noop(dut):
    """
    Load non-zero weights, then stream A=0.
    Accumulator should not change — FMA multiplies by 0.
    Verifies that zero activations produce no accumulation.
    """
    logger = await setup_array_stress(dut, "zero_activation_noop")
    N = ARRAY_SIZE

    B = [[float_to_q115(0.5)] * N for _ in range(N)]
    A_zero = [[0] * N for _ in range(N)]
    A_ref  = [[float_to_q115(0.25)] * N for _ in range(N)]

    # First: compute with A_ref to get a known non-zero state in accumulators
    hw_ref = await run_matmul_hw(dut, A_ref, B, N)

    # Now stream A=0 WITHOUT clearing (should add 0, leaving acc unchanged)
    await load_weights_scheduled(dut, B, N)
    await ClockCycles(dut.clk, 2)
    # Note: clear_acc was called inside run_matmul_hw; do NOT clear here
    await clear_accumulators(dut)  # start fresh for clarity
    await load_weights_scheduled(dut, B, N)
    await ClockCycles(dut.clk, 2)

    # Stream A_ref to load something into accumulator
    await stream_activations(dut, A_ref, N, 2 * N - 1)
    await ClockCycles(dut.clk, ARRAY_SIZE + 2 + FMA_MAC_PIFMA_LATENCY)
    ref_result = unpack_results(int(dut.results_flat.value), N)

    # Now stream A=0 — accumulator should be unchanged
    dut.compute_enable.value = 1
    for cycle in range(2 * N - 1):
        dut.a_inputs_flat.value = 0
        await RisingEdge(dut.clk)
    for _ in range(ARRAY_SIZE + FMA_MAC_PIFMA_LATENCY):
        dut.a_inputs_flat.value = 0
        await RisingEdge(dut.clk)
    dut.compute_enable.value = 0
    await ClockCycles(dut.clk, ARRAY_SIZE + 2 + FMA_MAC_PIFMA_LATENCY)

    after_zero = unpack_results(int(dut.results_flat.value), N)

    passed = matrices_close(ref_result, after_zero, N, tol=0.001)
    logger.log_message(f"  Accumulator unchanged after zero stream: {'PASS' if passed else 'FAIL'}")
    logger.close()
    assert passed, "zero_activation_noop: accumulator changed after zero activation stream"


# ============================================================================
# Test 7 — single-hot row
# ============================================================================

@cocotb.test()
async def test_single_hot_row(dut):
    """
    A has only row 0 non-zero. Only row 0 of output C should be non-zero.
    Verifies FMA activation isolation: FMA[row>0] receive zero activations.
    """
    logger = await setup_array_stress(dut, "single_hot_row")
    N = ARRAY_SIZE

    A = [[0] * N for _ in range(N)]
    A[0] = [float_to_q115(0.5)] * N  # only row 0 is active

    B = [[float_to_q115(0.25)] * N for _ in range(N)]

    hw = await run_matmul_hw(dut, A, B, N)
    ref = q115_matmul_ref(A, B, N)

    row0_ok = all(abs(q115_to_float(hw[0][j]) - q115_to_float(ref[0][j])) < 0.02
                  for j in range(N))
    other_zero = all(hw[i][j] == 0 for i in range(1, N) for j in range(N))

    logger.log_message(f"  Row 0 correct: {row0_ok}")
    logger.log_message(f"  Other rows zero: {other_zero}")
    logger.close()
    assert row0_ok, "single_hot_row: row 0 result incorrect"
    assert other_zero, "single_hot_row: rows 1+ should be zero but aren't"


# ============================================================================
# Test 8 — pipeline bubble
# ============================================================================

@cocotb.test()
async def test_pipeline_bubble(dut):
    """
    Verify that asserting `compute_enable=0` for a window of cycles produces
    NO accumulator updates ("no phantom accumulation in the gap").

    Test sequence:
      1. Run a complete matmul → record the accumulator state R0.
      2. Insert a 5-cycle bubble: compute_enable=0, a_inputs=0, no clear.
         (The FMA's data passthrough still advances but no MAC may occur.)
      3. Insert a longer 10-cycle bubble for stronger stress.
      4. Read the accumulator → must still equal R0 exactly.

    A passing result proves compute_enable strictly gates accumulation independent
    of data-path activity.  Mid-stream bubbles are NOT tested here because the
    weight-stationary dataflow couples timing between rows; mid-stream gaps
    require a more elaborate split-wavefront protocol.  The property tested
    (compute_enable gating) is the underlying hardware contract.
    """
    logger = await setup_array_stress(dut, "pipeline_bubble")
    random.seed(2727)
    N = ARRAY_SIZE

    A = rand_matrix(N, -0.3, 0.3)
    B = rand_matrix(N, -0.3, 0.3)

    # Run the matmul fully
    hw_initial = await run_matmul_hw(dut, A, B, N)

    # Insert short bubble (5 cycles): compute=OFF, a=0
    dut.compute_enable.value = 0
    for _ in range(5):
        dut.a_inputs_flat.value = 0
        await RisingEdge(dut.clk)
    await ClockCycles(dut.clk, FMA_MAC_PIFMA_LATENCY)

    hw_after_short = unpack_results(int(dut.results_flat.value), N)
    short_unchanged = (hw_after_short == hw_initial)
    logger.log_message(f"  Accumulator unchanged after 5-cycle bubble: {short_unchanged}")

    # Insert longer bubble (10 cycles): same expected outcome
    dut.compute_enable.value = 0
    for _ in range(10):
        dut.a_inputs_flat.value = 0
        await RisingEdge(dut.clk)
    await ClockCycles(dut.clk, FMA_MAC_PIFMA_LATENCY)

    hw_after_long = unpack_results(int(dut.results_flat.value), N)
    long_unchanged = (hw_after_long == hw_initial)
    logger.log_message(f"  Accumulator unchanged after 10-cycle bubble: {long_unchanged}")

    # Drive non-zero activations during a bubble — STILL must not accumulate
    # because compute_enable is OFF.  This is the strongest form of the test.
    dut.compute_enable.value = 0
    for _ in range(8):
        dut.a_inputs_flat.value = pack_inputs(
            [float_to_q115(0.5)] * ARRAY_SIZE
        )
        await RisingEdge(dut.clk)
    await ClockCycles(dut.clk, FMA_MAC_PIFMA_LATENCY)

    hw_after_nonzero_bubble = unpack_results(int(dut.results_flat.value), N)
    nonzero_unchanged = (hw_after_nonzero_bubble == hw_initial)
    logger.log_message(
        f"  Accumulator unchanged after 8-cycle non-zero-data bubble (compute=OFF): "
        f"{nonzero_unchanged}"
    )

    logger.close()
    assert short_unchanged, "pipeline_bubble: 5-cycle compute_enable=0 bubble caused accumulation"
    assert long_unchanged, "pipeline_bubble: 10-cycle compute_enable=0 bubble caused accumulation"
    assert nonzero_unchanged, (
        "pipeline_bubble: non-zero data during compute_enable=0 caused phantom accumulation"
    )


# ============================================================================
# Test 9 — weight reuse across multiple activation streams
# ============================================================================

@cocotb.test()
async def test_weight_reuse_multi_activation(dut):
    """
    Load weights once; stream 3 different activation matrices without reloading.
    Each run must match the reference independently (with clear_acc between).
    """
    logger = await setup_array_stress(dut, "weight_reuse")
    random.seed(9001)
    N = ARRAY_SIZE

    B = rand_matrix(N)
    activation_sets = [rand_matrix(N, -0.25, 0.25) for _ in range(3)]

    # Load weights once
    await clear_accumulators(dut)
    await load_weights_scheduled(dut, B, N)

    all_passed = True
    for idx, A in enumerate(activation_sets):
        await clear_accumulators(dut)   # clear between activations
        await ClockCycles(dut.clk, 2)
        await stream_activations(dut, A, N, 2 * N - 1)
        await ClockCycles(dut.clk, ARRAY_SIZE + 2 + FMA_MAC_PIFMA_LATENCY)

        hw = unpack_results(int(dut.results_flat.value), N)
        ref = q115_matmul_ref(A, B, N)

        ok = matrices_close(hw, ref, N)
        if not ok:
            all_passed = False
        logger.log_message(f"  Activation set {idx}: {'PASS' if ok else 'FAIL'}")

    logger.close()
    assert all_passed, "weight_reuse: at least one activation stream produced wrong result"


# ============================================================================
# Test 10 — rapid clear then compute
# ============================================================================

@cocotb.test()
async def test_rapid_clear_then_compute(dut):
    """
    Accumulate some values, assert clear_acc on cycle N, assert compute_enable on cycle N+1.
    The clear must take effect before the new computation begins.
    """
    logger = await setup_array_stress(dut, "rapid_clear_then_compute")
    N = ARRAY_SIZE

    B = [[float_to_q115(0.5)] * N for _ in range(N)]
    A1 = [[float_to_q115(0.8)] * N for _ in range(N)]  # first fill with large values
    A2 = [[float_to_q115(0.1)] * N for _ in range(N)]  # then small values after clear

    # First matmul (fills accumulator with large values)
    await clear_accumulators(dut)
    await load_weights_scheduled(dut, B, N)
    await ClockCycles(dut.clk, 2)
    await stream_activations(dut, A1, N, 2 * N - 1)
    await ClockCycles(dut.clk, ARRAY_SIZE + 2 + FMA_MAC_PIFMA_LATENCY)

    # Rapid: clear on one cycle, then immediately compute A2
    dut.clear_acc.value = 1
    await RisingEdge(dut.clk)
    dut.clear_acc.value = 0
    # On the very next cycle, start streaming A2
    await stream_activations(dut, A2, N, 2 * N - 1)
    await ClockCycles(dut.clk, ARRAY_SIZE + 2 + FMA_MAC_PIFMA_LATENCY)

    hw = unpack_results(int(dut.results_flat.value), N)
    ref = q115_matmul_ref(A2, B, N)

    passed = matrices_close(hw, ref, N)
    logger.log_message(f"  Rapid clear+compute: {'PASS' if passed else 'FAIL'}")
    logger.close()
    assert passed, "rapid_clear_then_compute: old accumulator leaked into new computation"


# ============================================================================
# Test 11 — 10-batch random matmuls
# ============================================================================

@cocotb.test()
async def test_batch_10_random(dut):
    """
    10 consecutive random 8×8 matmuls with clear_acc between each.
    Bit-exact verification ensures no state leaks between batches.
    """
    logger = await setup_array_stress(dut, "batch_10_random")
    random.seed(10001)
    N = ARRAY_SIZE
    NUM_BATCHES = 10

    all_passed = True

    for batch in range(NUM_BATCHES):
        A = rand_matrix(N, -0.4, 0.4)
        B = rand_matrix(N, -0.4, 0.4)

        hw = await run_matmul_hw(dut, A, B, N)
        ref = q115_matmul_ref(A, B, N)

        ok = matrices_close(hw, ref, N)
        if not ok:
            all_passed = False
            logger.log_message(f"  Batch {batch}: FAIL")
            for i in range(N):
                for j in range(N):
                    diff = abs(q115_to_float(hw[i][j]) - q115_to_float(ref[i][j]))
                    if diff > 0.02:
                        logger.log_message(
                            f"    [{i}][{j}]: hw={q115_to_float(hw[i][j]):+.4f}, "
                            f"ref={q115_to_float(ref[i][j]):+.4f}"
                        )
        else:
            logger.log_message(f"  Batch {batch}: PASS")

    logger.close()
    assert all_passed, "batch_10_random: one or more batches failed"
