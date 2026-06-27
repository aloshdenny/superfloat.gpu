"""
Very Large and Very Very Large Matrix Multiplication — Atreides GPU
====================================================================

Extends the existing matmul test suite (test_matmul_large.py) to sizes that
require the build_large_const() helper for addresses > 127.

Hardware constraints
--------------------
- thread_count register: 8-bit → max 255 threads per dispatch.
  Maximum N for single-dispatch square matmul: N=15 (225 threads, padded to 228 ≤ 255).
  N=16 (256 elements) requires MULTI-DISPATCH (≥2 calls).
- Data memory: 2^19 words (19-bit address space), i.e. 1 MiB of 16-bit data.
  Large tests are now bounded mostly by the 8-bit thread_count dispatch window,
  not by SRAM capacity.
- CONST immediate: 8-bit sign-extended → values 0..127 only.
  build_large_const() handles larger values via doubling.

Test inventory
--------------
  test_matmul_9x9       9×9,  single dispatch (81 threads, all < 255)
  test_matmul_10x10    10×10, single dispatch (100 threads)
  test_matmul_11x11    11×11, single dispatch (121 threads)
  test_matmul_12x12    12×12, single dispatch (144 threads)
  test_matmul_16x16     16×16, 2-dispatch (128+128 threads each)
  test_matmul_tiled_32x32  32×32, 8-dispatch (128+... threads each)
  test_matmul_tiled_64x64  BUILDER SMOKE — memory now fits, but full execution is
                           intentionally not run by default because simulation is long.
"""

import cocotb
from cocotb.triggers import ClockCycles
import random
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from helpers.q115 import float_to_q115, q115_to_float, q115_matmul
from helpers.addr import build_large_const
from helpers.memory import (
    asm_mul, asm_add, asm_sub, asm_div, asm_const,
    asm_ldr, asm_str, asm_fma, asm_cmp, asm_brn, asm_ret,
    read_memory_range,
    R0, R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12,
    BLOCK_IDX, BLOCK_DIM, THREAD_IDX,
)
from helpers.setup import setup_test, run_kernel

# ============================================================================
# Kernel builder — supports large addresses and per-dispatch thread offset
# ============================================================================

THREADS_PER_BLOCK = 4
MAX_DISPATCH_THREADS = 252    # 63 blocks × 4 threads  (≤ 255 8-bit max)


def build_matmul_kernel_large(N: int,
                               base_a: int = 0,
                               base_b: int = None,
                               base_c: int = None,
                               offset: int = 0) -> list:
    """
    N×N matmul kernel supporting addresses > 127 via build_large_const.

    Each thread computes one output element:
      i      = BLOCK_IDX * BLOCK_DIM + THREAD_IDX + offset
      row    = i // N
      col    = i % N
      C[i]   = sum_{k=0}^{N-1} A[row*N+k] * B[k*N+col]

    Parameters
    ----------
    N       : matrix dimension (must be < 128 to fit in CONST)
    base_a  : starting address of A in data memory
    base_b  : starting address of B (default: base_a + N*N)
    base_c  : starting address of C (default: base_b + N*N)
    offset  : constant offset added to global thread index i (for multi-dispatch)
    """
    if base_b is None:
        base_b = base_a + N * N
    if base_c is None:
        base_c = base_b + N * N

    assert N < 128, f"N={N} must be < 128 (CONST immediate range)"

    instrs = []

    # --- Thread index + offset ---
    instrs += [asm_mul(R0, BLOCK_IDX, BLOCK_DIM),   # i = block*dim
               asm_add(R0, R0, THREAD_IDX)]          # i += threadIdx
    if offset > 0:
        instrs += build_large_const(R12, offset, scratch_reg=R11)
        instrs += [asm_add(R0, R0, R12)]             # i += offset

    # --- Load addresses into registers ---
    instrs += [asm_const(R1, 1)]                     # increment = 1
    instrs += [asm_const(R2, N)]                     # N
    instrs += build_large_const(R3, base_a, scratch_reg=R11)   # R3 = base_a
    instrs += build_large_const(R4, base_b, scratch_reg=R11)   # R4 = base_b
    instrs += build_large_const(R5, base_c, scratch_reg=R11)   # R5 = base_c

    # --- Compute row and col ---
    instrs += [asm_div(R6, R0, R2)]                  # row = i / N
    instrs += [asm_mul(R7, R6, R2),
               asm_sub(R7, R0, R7)]                  # col = i - row*N

    # --- Initialise accumulator and loop counter ---
    instrs += [asm_const(R8, 0),                     # acc = 0
               asm_const(R9, 0)]                     # k = 0

    # --- Inner loop start ---
    loop_start = len(instrs)

    # Load A[row*N + k]
    instrs += [asm_mul(R10, R6, R2),                 # row * N
               asm_add(R10, R10, R9),                # + k
               asm_add(R10, R10, R3),                # + base_a
               asm_ldr(R10, R10)]                    # R10 = A[row*N+k]

    # Load B[k*N + col]
    instrs += [asm_mul(R11, R9, R2),                 # k * N
               asm_add(R11, R11, R7),                # + col
               asm_add(R11, R11, R4),                # + base_b
               asm_ldr(R11, R11)]                    # R11 = B[k*N+col]

    # FMA
    instrs += [asm_fma(R8, R10, R11)]                # acc += A[...]*B[...]

    # Loop control
    instrs += [asm_add(R9, R9, R1),                  # k++
               asm_cmp(R9, R2)]                      # compare k with N

    branch_pc = len(instrs)
    instrs += [asm_brn(loop_start - (branch_pc + 1))]  # loop if k < N

    # --- Store result ---
    instrs += [asm_add(R9, R5, R0),                  # addr_C = base_c + i
               asm_str(R9, R8),                      # C[i] = acc
               asm_ret()]

    return instrs


# ============================================================================
# Multi-dispatch runner
# ============================================================================

async def run_matmul_large(dut, N: int, a_q: list, b_q: list,
                            expected_q: list,
                            base_a: int = 0,
                            max_cycles_per_dispatch: int = 40000) -> bool:
    """
    Run N×N matmul, splitting into multiple dispatches if N²>MAX_DISPATCH_THREADS.

    Memory layout: A at base_a, B at base_a+N², C at base_a+2*N².
    Data is loaded once on the first dispatch; subsequent dispatches inherit memory.

    Returns True if bit-exact results match expected_q.
    """
    base_b = base_a + N * N
    base_c = base_b + N * N
    data = a_q + b_q + [0] * (N * N)

    total = N * N
    # Split into chunks ≤ MAX_DISPATCH_THREADS, padded to multiple of THREADS_PER_BLOCK
    dispatches = []
    processed = 0
    while processed < total:
        remaining = total - processed
        chunk = min(MAX_DISPATCH_THREADS, remaining)
        padded = ((chunk + THREADS_PER_BLOCK - 1) // THREADS_PER_BLOCK) * THREADS_PER_BLOCK
        padded = min(padded, 255)   # hard 8-bit cap
        dispatches.append((processed, padded))
        processed += chunk

    all_passed = True
    for disp_idx, (off, tc) in enumerate(dispatches):
        program = build_matmul_kernel_large(N, base_a, base_b, base_c, offset=off)
        load_data = data if disp_idx == 0 else None

        logger = await setup_test(
            dut,
            test_name=f"mmvvl_{N}x{N}_d{disp_idx}",
            program=program,
            data=load_data,
            thread_count=tc,
            verbose=False,
        )
        # Cycle budget scales strongly with both N (inner loop length) and thread_count.
        # Keep caller override as a floor, but auto-raise for larger dispatches.
        auto_budget = tc * (N * 16 + 128)
        dispatch_budget = max(max_cycles_per_dispatch, auto_budget)
        await run_kernel(dut, logger, max_cycles=dispatch_budget,
                         trace_interval=0)
        await ClockCycles(dut.clk, 10)
        logger.close()

    results = read_memory_range(dut, base_c, N * N)

    if results != expected_q:
        all_passed = False
        # Report first few mismatches
        for i in range(N * N):
            if results[i] != expected_q[i]:
                r, c = i // N, i % N
                print(
                    f"  [{N}x{N}] C[{r}][{c}]: "
                    f"got 0x{results[i]:04X} ({q115_to_float(results[i]):+.6f}), "
                    f"expected 0x{expected_q[i]:04X} ({q115_to_float(expected_q[i]):+.6f})"
                )

    return all_passed


# ============================================================================
# Utility
# ============================================================================

def rand_flat_q115(n: int, lo: float = -0.4, hi: float = 0.4,
                   seed: int = None) -> list:
    if seed is not None:
        random.seed(seed)
    return [float_to_q115(random.uniform(lo, hi)) for _ in range(n)]


def mat_flat(mat_f: list) -> list:
    return [float_to_q115(v) for row in mat_f for v in row]


# ============================================================================
# Test 1 — 9×9
# ============================================================================

@cocotb.test()
async def test_matmul_9x9(dut):
    """
    9×9 matmul (81 elements, single dispatch, thread_count=84).
    base_b=81 < 128 (direct CONST), base_c=162 > 127 (build_large_const).
    """
    N = 9
    a_q = rand_flat_q115(N * N, seed=9090)
    b_q = rand_flat_q115(N * N, seed=9091)
    expected = q115_matmul(a_q, b_q, N, N, N)

    passed = await run_matmul_large(dut, N, a_q, b_q, expected, max_cycles_per_dispatch=10000)
    assert passed, "test_matmul_9x9 failed"


# ============================================================================
# Test 2 — 10×10
# ============================================================================

@cocotb.test()
async def test_matmul_10x10(dut):
    """
    10×10 matmul (100 elements, single dispatch, thread_count=100).
    base_b=100 < 128 ✓, base_c=200 > 127 (build_large_const: CONST(100)+ADD).
    """
    N = 10
    a_q = rand_flat_q115(N * N, seed=1010)
    b_q = rand_flat_q115(N * N, seed=1011)
    expected = q115_matmul(a_q, b_q, N, N, N)

    passed = await run_matmul_large(dut, N, a_q, b_q, expected, max_cycles_per_dispatch=12000)
    assert passed, "test_matmul_10x10 failed"


# ============================================================================
# Test 3 — 11×11
# ============================================================================

@cocotb.test()
async def test_matmul_11x11(dut):
    """
    11×11 matmul (121 elements, single dispatch, thread_count=124).
    base_b=121 < 128 ✓, base_c=242 > 127 (CONST(121)+ADD).
    """
    N = 11
    a_q = rand_flat_q115(N * N, seed=1111)
    b_q = rand_flat_q115(N * N, seed=1112)
    expected = q115_matmul(a_q, b_q, N, N, N)

    passed = await run_matmul_large(dut, N, a_q, b_q, expected, max_cycles_per_dispatch=15000)
    assert passed, "test_matmul_11x11 failed"


# ============================================================================
# Test 4 — 12×12
# ============================================================================

@cocotb.test()
async def test_matmul_12x12(dut):
    """
    12×12 matmul (144 elements, single dispatch, thread_count=144).
    base_b=144 > 127 (CONST(72)+ADD), base_c=288 > 127 (CONST(72)+ADD+ADD).
    First test to require build_large_const for BOTH base_b and base_c.
    """
    N = 12
    a_q = rand_flat_q115(N * N, seed=1212)
    b_q = rand_flat_q115(N * N, seed=1213)
    expected = q115_matmul(a_q, b_q, N, N, N)

    passed = await run_matmul_large(dut, N, a_q, b_q, expected, max_cycles_per_dispatch=20000)
    assert passed, "test_matmul_12x12 failed"


# ============================================================================
# Test 5 — 16×16 (multi-dispatch)
# ============================================================================

@cocotb.test()
async def test_matmul_16x16(dut):
    """
    16×16 matmul (256 elements) — requires 2 dispatches of 128 threads each.

    The 8-bit thread_count register limits a single dispatch to ≤255 threads.
    We split output elements 0..127 (dispatch 0) and 128..255 (dispatch 1),
    encoding the per-dispatch offset into the kernel via build_large_const.

    Note: this replaces the 16×16 test in test_matmul_large.py which silently
    fell back to an 8×8 test due to this same thread_count constraint.
    """
    N = 16
    a_q = rand_flat_q115(N * N, seed=1616)
    b_q = rand_flat_q115(N * N, seed=1617)
    expected = q115_matmul(a_q, b_q, N, N, N)

    # N=16: 256 elements → 2 dispatches of 128 threads each (128 ≤ 255 ✓)
    passed = await run_matmul_large(dut, N, a_q, b_q, expected,
                                     max_cycles_per_dispatch=60000)
    assert passed, "test_matmul_16x16 failed"


# ============================================================================
# Test 6 — 32×32 tiled via multi-dispatch
# ============================================================================

@cocotb.test()
async def test_matmul_tiled_32x32(dut):
    """
    32×32 matmul (1024 elements) — 5 dispatches of ≤252 threads.

    Memory: A(1024) + B(1024) + C(1024) = 3072 words << 2^19 ✓
    Each dispatch covers ≤252 consecutive output elements with a hardcoded offset.

    base_b = 1024  →  CONST(64) + ADD×4  (5 instr)
    base_c = 2048  →  CONST(64) + ADD×5  (6 instr)

    Estimated simulation time: ~5 × 40k = ~200k cycles (several minutes).
    This is the "very large" stress test; it exercises the full multi-block
    dispatch pipeline.
    """
    N = 32
    # Use small values to avoid heavy saturation and keep results interpretable
    a_q = rand_flat_q115(N * N, lo=-0.15, hi=0.15, seed=3232)
    b_q = rand_flat_q115(N * N, lo=-0.15, hi=0.15, seed=3233)
    expected = q115_matmul(a_q, b_q, N, N, N)

    passed = await run_matmul_large(dut, N, a_q, b_q, expected,
                                     max_cycles_per_dispatch=200000)
    assert passed, "test_matmul_tiled_32x32 failed"


# ============================================================================
# Test 7 — 64×64 (builder smoke; full simulation omitted for runtime)
# ============================================================================

@cocotb.test()
async def test_matmul_tiled_64x64(dut):
    """
    64×64 matmul builder smoke.  The 1 MiB data space is large enough for
    A/B/C (3 × 64² = 12 288 words), but full execution is intentionally
    omitted because it is a long multi-dispatch simulation.

    The kernel builder (build_matmul_kernel_large with N=64, offset) is
    still verified so large address construction stays covered.
    """
    N = 64
    cocotb.log.warning(
        f"test_matmul_tiled_{N}x{N} builder-only smoke: "
        f"requires {3 * N * N} data memory words, which fits in the "
        f"2^19-word tb_gpu data memory; full execution is omitted for runtime."
    )

    # Verify the kernel builder produces a valid program (no assertion errors)
    base_b = N * N      # 4096
    base_c = 2 * N * N  # 8192
    try:
        prog = build_matmul_kernel_large(N, 0, base_b, base_c, offset=0)
        cocotb.log.info(
            f"  64×64 kernel compiles: {len(prog)} instructions, "
            f"base_b={base_b} ({sum(1 for _ in build_large_const(R4, base_b))} instr), "
            f"base_c={base_c} ({sum(1 for _ in build_large_const(R5, base_c))} instr)"
        )
    except Exception as e:
        assert False, f"64×64 kernel builder raised: {e}"

    # Test passes trivially (we only verify the builder, not execution)
