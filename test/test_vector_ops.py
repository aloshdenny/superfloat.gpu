"""
SF16 Vector and Arithmetic Operations Test Suite — Atreides GPU

Tests GPU-level SF16 vector operations dispatched as kernels:
- Element-wise saturating add (ACT func=none)
- Element-wise subtract (ACT with pre-negated operand)
- Vector scale by scalar (FMA with acc=0)
- Dot product accumulation chains (16-element and 64-element)
- Saturation stress (max+max, min+min)
- Underflow (LSB × LSB → 0)
- Alternating-sign accumulation (sign cancellation fidelity)

Architecture note: SF16 saturating add uses the ACT instruction with Rd
having bits[1:0]=00 (func=none). Rd=R8 (8 & 3 = 0) satisfies this.
"""

import cocotb
from cocotb.triggers import ClockCycles
import random
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from helpers.q115 import (
    float_to_q115, q115_to_float,
    q115_add, q115_sub, q115_mul, q115_fma, q115_relu,
)
from helpers.memory import (
    asm_mul, asm_add, asm_sub, asm_div, asm_const,
    asm_ldr, asm_str, asm_fma, asm_act, asm_cmp, asm_brn, asm_ret,
    init_data_memory, read_memory_range,
    R0, R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12,
    BLOCK_IDX, BLOCK_DIM, THREAD_IDX,
)
from helpers.setup import setup_test, run_kernel

# ============================================================================
# Kernel builders
# ============================================================================

THREADS_PER_BLOCK = 2


def build_vec_add_kernel(base_a: int, base_b: int, base_out: int) -> list:
    """
    Element-wise saturating add: out[i] = saturate(a[i] + b[i]).
    Uses ACT Rd=R8 (R8=8, bits[1:0]=00 → func=none = saturating add).
    base_a, base_b, base_out must be ≤ 127 (CONST range).
    """
    return [
        asm_mul(R9, BLOCK_IDX, BLOCK_DIM),   # R9 = thread_i (preserved)
        asm_add(R9, R9, THREAD_IDX),
        asm_const(R1, base_a),
        asm_const(R2, base_b),
        asm_const(R3, base_out),
        asm_add(R4, R1, R9),                  # addr_a = base_a + i
        asm_ldr(R4, R4),                       # R4 = a[i]
        asm_add(R5, R2, R9),                   # addr_b = base_b + i
        asm_ldr(R5, R5),                       # R5 = b[i]
        asm_act(R8, R4, R5),                   # R8 = saturate(a[i]+b[i]), func=none (8&3=0)
        asm_add(R7, R3, R9),                   # addr_out = base_out + i
        asm_str(R7, R8),                       # out[i] = R8
        asm_ret(),
    ]


def build_vec_scale_kernel(base_a: int, base_scalar_addr: int, base_out: int) -> list:
    """
    Element-wise scale: out[i] = a[i] * scalar  (Q1.15, acc=0).
    Scalar is loaded from data_memory[base_scalar_addr] (single shared value).
    Uses FMA: R8 = FMA(acc=0, a[i], scalar) = a[i]*scalar.
    """
    return [
        asm_mul(R9, BLOCK_IDX, BLOCK_DIM),
        asm_add(R9, R9, THREAD_IDX),
        asm_const(R1, base_a),
        asm_const(R2, base_scalar_addr),
        asm_const(R3, base_out),
        asm_add(R4, R1, R9),
        asm_ldr(R4, R4),                       # R4 = a[i]
        asm_ldr(R5, R2),                       # R5 = scalar
        asm_const(R8, 0),                      # R8 = 0 (initial acc)
        asm_fma(R8, R4, R5),                   # R8 = a[i]*scalar
        asm_add(R7, R3, R9),
        asm_str(R7, R8),
        asm_ret(),
    ]


def build_dot_product_kernel(N: int, base_a: int, base_b: int, base_out: int) -> list:
    """
    All threads compute the same dot product: out[thread_i] = sum_k a[k]*b[k].
    We only check out[0] in the test; other threads write redundant copies.
    N, base_a, base_b must each be ≤ 127.
    base_out=2*N: if N≤63 → 2*N≤126 < 128 ✓ for N≤63.
    For N=64 call with base_out=127 (base_b=64, base_out=127 < 128).
    """
    instrs = [
        # Thread index (used only for output address)
        asm_mul(R9, BLOCK_IDX, BLOCK_DIM),
        asm_add(R9, R9, THREAD_IDX),
        # Constants
        asm_const(R1, 1),                      # increment
        asm_const(R2, base_a),
        asm_const(R3, base_b),
        asm_const(R4, base_out),
        asm_const(R8, 0),                      # acc = 0
        asm_const(R5, 0),                      # k = 0
        asm_const(R6, N),                      # k_end = N
    ]

    loop_start = len(instrs)   # dynamic: avoids off-by-one in branch offset

    instrs += [
        asm_add(R10, R2, R5),                  # addr_a = base_a + k
        asm_ldr(R10, R10),                     # R10 = a[k]
        asm_add(R11, R3, R5),                  # addr_b = base_b + k
        asm_ldr(R11, R11),                     # R11 = b[k]
        asm_fma(R8, R10, R11),                 # acc += a[k]*b[k]
        asm_add(R5, R5, R1),                   # k++
        asm_cmp(R5, R6),                       # compare k with N
    ]

    branch_pc = len(instrs)                    # index of the BRN instruction
    instrs.append(asm_brn(loop_start - (branch_pc + 1)))   # branch if k < N

    instrs += [
        asm_add(R7, R4, R9),                   # addr_out = base_out + thread_i
        asm_str(R7, R8),                       # out[thread_i] = acc
        asm_ret(),
    ]

    return instrs


# Reference: dot product in Q1.15
def ref_dot_product(a: list, b: list) -> int:
    acc = 0
    for i in range(len(a)):
        acc = q115_fma(acc, a[i], b[i])
    return acc


# ============================================================================
# Test 1 — test_vec_add_4
# ============================================================================

@cocotb.test()
async def test_vec_add_4(dut):
    """
    4-element Q1.15 saturating vector add: out[i] = saturate(a[i] + b[i]).
    Tests multiple sign combinations and value magnitudes.
    """
    N = 4
    # Memory layout: a[0..3], b[4..7], out[8..11]
    base_a, base_b, base_out = 0, 4, 8

    cases = [
        ("pos_pos",   [0.5, 0.25, 0.125, 0.0625],  [0.25, 0.5, 0.25, 0.125]),
        ("neg_pos",   [-0.5, -0.25, 0.125, -0.125], [0.5, 0.25, 0.5, 0.25]),
        ("mixed",     [0.25, -0.5, 0.75, -0.25],    [-0.25, 0.5, -0.375, 0.25]),
        ("cancel",    [0.5, -0.5, 0.25, -0.25],     [-0.5, 0.5, -0.25, 0.25]),
    ]

    program = build_vec_add_kernel(base_a, base_b, base_out)

    for name, a_f, b_f in cases:
        a_q = [float_to_q115(x) for x in a_f]
        b_q = [float_to_q115(x) for x in b_f]
        expected = [q115_add(a_q[i], b_q[i]) for i in range(N)]

        data = a_q + b_q + [0] * N
        logger = await setup_test(dut, f"vec_add_4_{name}", program, data,
                                  thread_count=N, verbose=False)
        await run_kernel(dut, logger, max_cycles=500, trace_interval=0)
        await ClockCycles(dut.clk, 10)

        results = read_memory_range(dut, base_out, N)
        passed = results == expected

        if not passed:
            for i in range(N):
                if results[i] != expected[i]:
                    logger.log_message(
                        f"  [{name}] C[{i}]: got 0x{results[i]:04X} "
                        f"({q115_to_float(results[i]):+.4f}), "
                        f"expected 0x{expected[i]:04X} ({q115_to_float(expected[i]):+.4f})"
                    )
        logger.close()
        assert passed, f"vec_add_4 case '{name}' failed"


# ============================================================================
# Test 2 — test_vec_sub_4
# ============================================================================

@cocotb.test()
async def test_vec_sub_4(dut):
    """
    4-element Q1.15 vector subtract: out[i] = saturate(a[i] - b[i]).
    Implemented as ACT saturating add with pre-negated b: store (-b) in memory,
    then out[i] = a[i] + (-b[i]).  Semantically identical to q115_sub.
    """
    N = 4
    base_a, base_neg_b, base_out = 0, 4, 8

    cases = [
        ("basic",     [0.5, 0.25, 0.75, -0.25],  [0.25, 0.125, 0.5, -0.5]),
        ("neg_minus", [-0.5, -0.25, 0.0, 0.5],   [0.25, -0.125, 0.25, 0.5]),
        ("zeros",     [0.0, 0.0, 0.5, -0.5],     [0.0, 0.0, 0.5, -0.5]),
        ("quarter",   [0.25, -0.25, 0.125, 0.5], [-0.25, 0.25, -0.125, 0.25]),
    ]

    program = build_vec_add_kernel(base_a, base_neg_b, base_out)

    for name, a_f, b_f in cases:
        a_q = [float_to_q115(x) for x in a_f]
        b_q = [float_to_q115(x) for x in b_f]
        # Pre-negate b: -b_q[i] in Q1.15 = q115_sub(0, b_q[i])
        neg_b_q = [q115_sub(0, b_q[i]) for i in range(N)]
        expected = [q115_sub(a_q[i], b_q[i]) for i in range(N)]

        data = a_q + neg_b_q + [0] * N
        logger = await setup_test(dut, f"vec_sub_4_{name}", program, data,
                                  thread_count=N, verbose=False)
        await run_kernel(dut, logger, max_cycles=500, trace_interval=0)
        await ClockCycles(dut.clk, 10)

        results = read_memory_range(dut, base_out, N)
        passed = results == expected

        if not passed:
            for i in range(N):
                if results[i] != expected[i]:
                    logger.log_message(
                        f"  [{name}] [{i}]: got 0x{results[i]:04X}, "
                        f"expected 0x{expected[i]:04X}"
                    )
        logger.close()
        assert passed, f"vec_sub_4 case '{name}' failed"


# ============================================================================
# Test 3 — test_vec_scale_8
# ============================================================================

@cocotb.test()
async def test_vec_scale_8(dut):
    """
    8-element Q1.15 vector scale: out[i] = a[i] * scalar.
    FMA with acc=0: out = FMA(0, a[i], scalar).
    Tests various scalars including 0, 1.0 (approx), -1.0 (approx), and 0.5.
    """
    N = 8
    base_a, base_scalar, base_out = 0, N, N + 1

    scalars = [
        ("half",     0.5),
        ("quarter",  0.25),
        ("neg_half", -0.5),
        ("near_one", 32767 / 32768),    # Q115_MAX ≈ 1.0
        ("zero",     0.0),
        ("small",    0.125),
    ]

    for name, scalar_f in scalars:
        a_f = [0.5, -0.25, 0.125, 0.75, -0.5, 0.25, -0.125, 0.375]
        a_q = [float_to_q115(x) for x in a_f]
        scalar_q = float_to_q115(scalar_f)
        expected = [q115_mul(a_q[i], scalar_q) for i in range(N)]

        data = a_q + [scalar_q, 0] + [0] * N
        program = build_vec_scale_kernel(base_a, base_scalar, base_out)

        logger = await setup_test(dut, f"vec_scale_8_{name}", program, data,
                                  thread_count=N, verbose=False)
        await run_kernel(dut, logger, max_cycles=500, trace_interval=0)
        await ClockCycles(dut.clk, 10)

        results = read_memory_range(dut, base_out, N)

        # Allow 1 LSB tolerance (truncation vs rounding in FMA pipeline)
        def close(a, b):
            a_s = a if a < 32768 else a - 65536
            b_s = b if b < 32768 else b - 65536
            return abs(a_s - b_s) <= 1

        passed = all(close(results[i], expected[i]) for i in range(N))
        if not passed:
            for i in range(N):
                if not close(results[i], expected[i]):
                    logger.log_message(
                        f"  [{name}] [{i}]: got 0x{results[i]:04X} "
                        f"({q115_to_float(results[i]):+.4f}), "
                        f"expected 0x{expected[i]:04X} ({q115_to_float(expected[i]):+.4f})"
                    )
        logger.close()
        assert passed, f"vec_scale_8 case '{name}' failed"


# ============================================================================
# Test 4 — test_vec_dot_product_16
# ============================================================================

@cocotb.test()
async def test_vec_dot_product_16(dut):
    """
    16-element Q1.15 dot product: result = sum_i a[i]*b[i].
    Single inner-loop FMA chain. Bit-exact vs Python reference.
    Memory: a[0..15] at 0, b[16..31] at 16, out[32..35] at 32.
    """
    N = 16
    base_a, base_b, base_out = 0, N, 2 * N
    thread_count = THREADS_PER_BLOCK  # 4 threads all compute same dot product

    random.seed(1601)
    cases = [
        ("uniform_pos",  [0.1] * N,                          [0.1] * N),
        ("alternating",  [0.5 if i % 2 == 0 else -0.5 for i in range(N)],
                         [0.5] * N),
        ("diminishing",  [0.5 / (2 ** i) for i in range(N)], [0.5] * N),
        ("random",       [random.uniform(-0.4, 0.4) for _ in range(N)],
                         [random.uniform(-0.4, 0.4) for _ in range(N)]),
    ]

    program = build_dot_product_kernel(N, base_a, base_b, base_out)

    for name, a_f, b_f in cases:
        a_q = [float_to_q115(x) for x in a_f]
        b_q = [float_to_q115(x) for x in b_f]
        expected = ref_dot_product(a_q, b_q)

        data = a_q + b_q + [0] * thread_count
        logger = await setup_test(dut, f"dot16_{name}", program, data,
                                  thread_count=thread_count, verbose=False)
        await run_kernel(dut, logger, max_cycles=2000, trace_interval=0)
        await ClockCycles(dut.clk, 10)

        result = read_memory_range(dut, base_out, 1)[0]
        passed = result == expected

        if not passed:
            logger.log_message(
                f"  [{name}] got 0x{result:04X} ({q115_to_float(result):+.6f}), "
                f"expected 0x{expected:04X} ({q115_to_float(expected):+.6f})"
            )
        logger.close()
        assert passed, f"dot_product_16 case '{name}' failed"


# ============================================================================
# Test 5 — test_vec_dot_product_64
# ============================================================================

@cocotb.test()
async def test_vec_dot_product_64(dut):
    """
    64-element Q1.15 dot product: accumulation drift and precision check.

    Memory layout: a[0..63] at 0, b[64..127] at 64, out at 127 (single slot).
    base_out=127 < 128, so CONST can load it directly.
    All 4 threads compute the full dot product and write to out[0..3].
    We check only out[0].
    """
    N = 64
    # Layout: out[0..3] at 0..3, a[0..63] at 4..67, b[0..63] at 68..131
    # All addresses < 128, no overlap between out range (0..3) and read ranges (4..131).
    base_out, base_a, base_b = 0, 4, 68
    thread_count = THREADS_PER_BLOCK

    random.seed(6401)
    cases = [
        ("uniform_tiny",  [0.01] * N, [0.01] * N),
        ("random_small",  [random.uniform(-0.2, 0.2) for _ in range(N)],
                          [random.uniform(-0.2, 0.2) for _ in range(N)]),
        ("alternating64", [0.1 if i % 2 == 0 else -0.1 for i in range(N)],
                          [0.5] * N),
    ]

    program = build_dot_product_kernel(N, base_a, base_b, base_out)

    for name, a_f, b_f in cases:
        a_q = [float_to_q115(x) for x in a_f]
        b_q = [float_to_q115(x) for x in b_f]
        expected = ref_dot_product(a_q, b_q)

        # Layout: [out[0..3]=0,0,0,0] [a[0..63]] [b[0..63]] = 4 + 64 + 64 = 132 slots
        # All threads write to out[i]=addr 0..3; we check out[0] at addr 0.
        data = [0] * 4 + a_q + b_q

        logger = await setup_test(dut, f"dot64_{name}", program, data,
                                  thread_count=thread_count, verbose=False)
        await run_kernel(dut, logger, max_cycles=50000, trace_interval=0)
        await ClockCycles(dut.clk, 10)

        result = read_memory_range(dut, base_out, 1)[0]
        passed = result == expected

        if not passed:
            logger.log_message(
                f"  [{name}] got 0x{result:04X} ({q115_to_float(result):+.6f}), "
                f"expected 0x{expected:04X} ({q115_to_float(expected):+.6f})"
            )
        logger.close()
        assert passed, f"dot_product_64 case '{name}' failed"


# ============================================================================
# Test 6 — test_vec_add_saturation
# ============================================================================

@cocotb.test()
async def test_vec_add_saturation(dut):
    """
    Q1.15 saturating add: verify ACT clamps correctly at ±boundaries.
    - Q115_MAX + Q115_MAX → Q115_MAX
    - Q115_MIN + Q115_MIN → Q115_MIN
    - Q115_MAX + 0x0001 → Q115_MAX
    - Q115_MIN + 0xFFFF (= -LSB) → Q115_MIN
    """
    N = 4
    Q115_MAX = 0x7FFF
    Q115_MIN = 0xFFFF  # most negative SF16 (sign=1, mantissa=0x7FFF = -0.999969)

    base_a, base_b, base_out = 0, 4, 8

    a_q = [Q115_MAX, Q115_MIN, Q115_MAX, Q115_MIN]
    b_q = [Q115_MAX, Q115_MIN, 0x0001,   0xFFFF]
    # q115_add saturates: max+max=max, min+min=min, max+lsb=max, min+(-lsb)=min
    expected = [q115_add(a_q[i], b_q[i]) for i in range(N)]

    program = build_vec_add_kernel(base_a, base_b, base_out)
    data = a_q + b_q + [0] * N

    logger = await setup_test(dut, "vec_add_saturation", program, data,
                              thread_count=N, verbose=False)
    await run_kernel(dut, logger, max_cycles=500, trace_interval=0)
    await ClockCycles(dut.clk, 10)

    results = read_memory_range(dut, base_out, N)
    passed = results == expected

    for i in range(N):
        status = "PASS" if results[i] == expected[i] else "FAIL"
        logger.log_message(
            f"  [{i}] a=0x{a_q[i]:04X} + b=0x{b_q[i]:04X} "
            f"= 0x{results[i]:04X} (expected 0x{expected[i]:04X}) [{status}]"
        )
    logger.close()
    assert passed, "vec_add_saturation failed"


# ============================================================================
# Test 7 — test_vec_underflow
# ============================================================================

@cocotb.test()
async def test_vec_underflow(dut):
    """
    Q1.15 underflow: LSB × LSB = 2^-30 rounds to 0 in Q1.15.
    Also tests very small values that lose precision in fixed-point.

    With FMA:  FMA(acc=0, a[i]=0x0001, b[scalar]=0x0001)
    Product magnitude: 1 * 1 = 1 (Q1.15 × Q1.15 = Q1.31, >> 15 → 0).
    So result = 0.
    """
    N = 4
    base_a, base_scalar, base_out = 0, N, N + 1

    LSB = 0x0001    # +2^-15 ≈ 3.05e-5
    TWO_LSB = 0x0002

    # LSB*LSB: magnitude product=1, >>15=0 → 0
    # 2LSB * 0x4000 (0.5): product=2*0x4000=0x8000 >> 15 = 1 → +LSB
    # 0x0001 * 0x0100: 0x0001*0x0100=0x100 >> 15 = 0 → 0 (still underflows)
    # 0x0010 * 0x0010: 16*16=256 >> 15 = 0 → 0
    cases = [
        ("lsb_x_lsb",    [LSB]*N,     LSB,       0),          # underflows to 0
        ("lsb_x_half",   [LSB]*N,     0x4000,    LSB),         # 2^-15 * 0.5 = 2^-16... rounds to 0 or LSB
        ("2lsb_x_half",  [TWO_LSB]*N, 0x4000,    LSB),         # 2*2^-15 * 0.5 = 2^-15 = LSB
        ("small_x_zero", [0x0100]*N,  0x0001,    0),           # small * near-zero → 0
    ]

    program = build_vec_scale_kernel(base_a, base_scalar, base_out)

    for name, a_raw, scalar_raw, expected_val in cases:
        # Use Q1.15 reference for exact expected
        expected = [q115_mul(a_raw[i], scalar_raw) for i in range(N)]
        data = a_raw + [scalar_raw, 0] + [0] * N

        logger = await setup_test(dut, f"underflow_{name}", program, data,
                                  thread_count=N, verbose=False)
        await run_kernel(dut, logger, max_cycles=500, trace_interval=0)
        await ClockCycles(dut.clk, 10)

        results = read_memory_range(dut, base_out, N)

        def close(a, b):
            a_s = a if a < 32768 else a - 65536
            b_s = b if b < 32768 else b - 65536
            return abs(a_s - b_s) <= 1

        passed = all(close(results[i], expected[i]) for i in range(N))
        if not passed:
            for i in range(N):
                if not close(results[i], expected[i]):
                    logger.log_message(
                        f"  [{name}] [{i}]: got 0x{results[i]:04X}, "
                        f"expected 0x{expected[i]:04X}"
                    )
        logger.close()
        assert passed, f"vec_underflow case '{name}' failed"


# ============================================================================
# Test 8 — test_vec_alternating_accumulation
# ============================================================================

@cocotb.test()
async def test_vec_alternating_accumulation(dut):
    """
    Alternating-sign dot product to verify sign-cancellation fidelity.

    Tests:
    - sum(+a[i]*b) alternating with -a[i]*b → result near 0
    - sum of strictly positive terms (monotone accumulation)
    - sum of strictly negative terms (monotone negative)
    - Alternating sequence that perfectly cancels → 0
    """
    N = 8
    base_a, base_b, base_out = 0, N, 2 * N
    thread_count = THREADS_PER_BLOCK

    half = float_to_q115(0.5)
    neg_half = float_to_q115(-0.5)
    quarter = float_to_q115(0.25)

    cases = [
        # Strictly positive accumulation
        ("all_pos",
         [float_to_q115(0.1)] * N,
         [float_to_q115(0.1)] * N),
        # Strictly negative accumulation
        ("all_neg",
         [float_to_q115(-0.1)] * N,
         [float_to_q115(0.1)] * N),
        # Perfect sign cancellation: +0.5*0.5 + (-0.5)*0.5 + ... = 0
        ("perfect_cancel",
         [half, neg_half, half, neg_half, half, neg_half, half, neg_half],
         [quarter, quarter, quarter, quarter, quarter, quarter, quarter, quarter]),
        # Imbalanced: 6 positive + 2 negative → positive result
        ("imbalanced",
         [float_to_q115(0.2) if i < 6 else float_to_q115(-0.3) for i in range(N)],
         [float_to_q115(0.25)] * N),
    ]

    program = build_dot_product_kernel(N, base_a, base_b, base_out)

    for name, a_q, b_q in cases:
        expected = ref_dot_product(a_q, b_q)
        data = a_q + b_q + [0] * thread_count

        logger = await setup_test(dut, f"alt_accum_{name}", program, data,
                                  thread_count=thread_count, verbose=False)
        await run_kernel(dut, logger, max_cycles=1500, trace_interval=0)
        await ClockCycles(dut.clk, 10)

        result = read_memory_range(dut, base_out, 1)[0]

        # Allow 1 LSB tolerance per accumulation step
        result_s = result if result < 32768 else result - 65536
        expected_s = expected if expected < 32768 else expected - 65536
        passed = abs(result_s - expected_s) <= 1

        if not passed:
            logger.log_message(
                f"  [{name}] got 0x{result:04X} ({q115_to_float(result):+.6f}), "
                f"expected 0x{expected:04X} ({q115_to_float(expected):+.6f})"
            )
        logger.close()
        assert passed, f"alternating_accumulation case '{name}' failed"
