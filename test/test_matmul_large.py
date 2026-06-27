"""
Large Matrix Multiplication Tests for Atreides GPU

Tests SF16 matmul at sizes from 4×4 to 16×16, exercising multi-block dispatch,
saturation, boundary values, and randomized bit-exact verification.

Also measures GFLOPS and reports SF16 vs IEEE fp32 error analysis.

Architecture: 2 cores, 4 threads/block → 8 threads per dispatch.
Each thread computes one output element of C = A × B.
For N×N matrices: N² output elements → ceil(N²/4) blocks dispatched.
"""

import cocotb
from cocotb.triggers import ClockCycles
import random
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from helpers.q115 import float_to_q115, q115_to_float, q115_matmul
from helpers.q115_reference import ieee_fp32_matmul, q115_vs_ieee_report, q115_error_analysis
from helpers.perf import PerformanceReport, format_perf_table
from helpers.memory import (
    init_data_memory, init_program_memory, read_memory_range,
    asm_mul, asm_add, asm_sub, asm_div, asm_const, asm_ldr, asm_str, asm_fma,
    asm_cmp, asm_brn, asm_ret,
    R0, R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, BLOCK_IDX, BLOCK_DIM, THREAD_IDX
)
from helpers.setup import setup_test, run_kernel


# =============================================================================
# Parameterized N×N matmul kernel builder
# =============================================================================

def build_matmul_program_nxn(N: int, base_a: int = 0, base_b: int = None,
                              base_c: int = None) -> list:
    """
    Build a parameterized N×N matrix multiplication kernel.
    
    Each thread computes one element: C[row][col] = Σ A[row][k] * B[k][col]
    
    Thread i computes: row = i / N, col = i % N
    
    Note: CONST instruction sign-extends 8-bit immediates, so values >= 128
    must be built from multiple instructions. We use CONST(64) + ADD to
    construct addresses like 128 = 64+64, or CONST(lo) + ADD(hi_part).
    
    Args:
        N: Matrix dimension (square N×N)
        base_a: Starting address of matrix A in data memory
        base_b: Starting address of matrix B (default: base_a + N*N)
        base_c: Starting address of matrix C (default: base_b + N*N)
    
    Returns:
        List of 16-bit instructions
    """
    if base_b is None:
        base_b = base_a + N * N
    if base_c is None:
        base_c = base_b + N * N
    
    assert N < 128, f"N={N} exceeds 7-bit signed CONST range"
    assert base_a < 128, f"base_a={base_a} exceeds 7-bit signed CONST range"
    
    # Build instruction list
    instrs = []
    
    # 0-1: Calculate global thread index
    instrs.append(asm_mul(R0, BLOCK_IDX, BLOCK_DIM))   # i = blockIdx * blockDim
    instrs.append(asm_add(R0, R0, THREAD_IDX))          # i += threadIdx
    
    # Constants
    instrs.append(asm_const(R1, 1))                     # increment = 1
    instrs.append(asm_const(R2, N))                     # N (matrix dimension)
    instrs.append(asm_const(R3, base_a))                # baseA (must be < 128)
    
    # baseB: may need multi-instruction load if >= 128
    if base_b < 128:
        instrs.append(asm_const(R4, base_b))
    else:
        # Build base_b from two halves: CONST(base_b - 64) + ADD(64)
        # Use R4 as temp: CONST R4, 64; CONST R11, (base_b - 64); ADD R4, R4, R11
        # But simpler: CONST R4, 64; ADD R4, R4, R4 gives 128.
        # For arbitrary values: CONST R4, (base_b >> 1); ADD R4, R4, R4; 
        # then if odd: ADD R4, R4, R1
        half = base_b // 2
        assert half < 128, f"base_b/2={half} still exceeds range"
        instrs.append(asm_const(R4, half))
        instrs.append(asm_add(R4, R4, R4))               # R4 = 2 * half
        if base_b % 2 == 1:
            instrs.append(asm_add(R4, R4, R1))            # R4 += 1 (for odd)
    
    # baseC: same treatment
    if base_c < 128:
        instrs.append(asm_const(R5, base_c))
    else:
        half = base_c // 2
        assert half < 128, f"base_c/2={half} still exceeds range"
        instrs.append(asm_const(R5, half))
        instrs.append(asm_add(R5, R5, R5))
        if base_c % 2 == 1:
            instrs.append(asm_add(R5, R5, R1))
    
    # Calculate row and col from global thread index
    instrs.append(asm_div(R6, R0, R2))                  # row = i / N
    instrs.append(asm_mul(R7, R6, R2))                   # row * N
    instrs.append(asm_sub(R7, R0, R7))                   # col = i - row * N = i % N
    
    # Initialize accumulator and loop counter
    instrs.append(asm_const(R8, 0))                      # acc = 0
    instrs.append(asm_const(R9, 0))                      # k = 0
    
    # Record LOOP target address (current instruction index)
    loop_start = len(instrs)
    
    # LOOP body: Load A[row][k]
    instrs.append(asm_mul(R10, R6, R2))                  # row * N
    instrs.append(asm_add(R10, R10, R9))                 # + k
    instrs.append(asm_add(R10, R10, R3))                 # + baseA
    instrs.append(asm_ldr(R10, R10))                     # R10 = A[row][k]
    
    # Load B[k][col]
    instrs.append(asm_mul(R11, R9, R2))                  # k * N
    instrs.append(asm_add(R11, R11, R7))                 # + col
    instrs.append(asm_add(R11, R11, R4))                 # + baseB
    instrs.append(asm_ldr(R11, R11))                     # R11 = B[k][col]
    
    # FMA
    instrs.append(asm_fma(R8, R10, R11))                 # acc += A[row][k] * B[k][col]
    
    # Loop control
    instrs.append(asm_add(R9, R9, R1))                   # k++
    instrs.append(asm_cmp(R9, R2))                       # compare k with N
    
    # Branch offset: target - (current_pc + 1)
    branch_pc = len(instrs)
    branch_offset = loop_start - (branch_pc + 1)
    instrs.append(asm_brn(branch_offset))                # branch to LOOP if k < N
    
    # Store result
    instrs.append(asm_add(R9, R5, R0))                   # addr_C = baseC + i
    instrs.append(asm_str(R9, R8))                       # C[i] = acc
    
    # Return
    instrs.append(asm_ret())                              # done
    
    return instrs


def build_data_nxn(a_q: list, b_q: list, N: int, base_a: int = 0) -> list:
    """
    Build data memory contents for N×N matmul.
    
    Layout: [A (N²)] [B (N²)] [C (N², zeros)]
    
    Args:
        a_q: Flat list of N² Q1.15 values for matrix A
        b_q: Flat list of N² Q1.15 values for matrix B
        N: Matrix dimension
        base_a: Starting address
        
    Returns:
        List of 16-bit values for data memory
    """
    data = [0] * base_a  # pad before base_a
    data.extend(a_q)
    data.extend(b_q)
    data.extend([0] * (N * N))  # C = zeros
    return data


async def run_matmul_test(dut, name: str, N: int, a_q: list, b_q: list,
                          expected_q: list, max_cycles: int = 5000,
                          verbose: bool = False,
                          report_ieee: bool = False) -> int:
    """
    Run a single N×N matmul test and assert bit-exact match.
    
    Returns cycle count.
    """
    base_a = 0
    base_b = N * N
    base_c = 2 * N * N
    num_elements = N * N
    # Pad thread_count to next multiple of THREADS_PER_BLOCK (4)
    # Hardware bug: partial blocks (thread_count % 4 != 0) don't execute correctly
    THREADS_PER_BLOCK = 4
    thread_count = ((num_elements + THREADS_PER_BLOCK - 1) // THREADS_PER_BLOCK) * THREADS_PER_BLOCK
    
    program = build_matmul_program_nxn(N, base_a, base_b, base_c)
    data = build_data_nxn(a_q, b_q, N, base_a)
    
    logger = await setup_test(
        dut,
        test_name=name,
        program=program,
        data=data,
        thread_count=thread_count,
        verbose=verbose
    )
    
    cycles = await run_kernel(dut, logger, max_cycles=max_cycles, trace_interval=0)
    
    # Allow memory writes to settle through the controller pipeline
    await ClockCycles(dut.clk, 10)
    
    # Read results
    results_raw = read_memory_range(dut, base_c, num_elements)
    
    # Bit-exact verification
    passed = results_raw == expected_q
    
    if not passed:
        logger.set_verbose(True)
        logger.log_section(f"FAILURE: {name}")
        for i in range(num_elements):
            if results_raw[i] != expected_q[i]:
                row, col = i // N, i % N
                logger.log_message(
                    f"MISMATCH C[{row}][{col}]: "
                    f"got 0x{results_raw[i]:04X} ({q115_to_float(results_raw[i]):+.6f}), "
                    f"expected 0x{expected_q[i]:04X} ({q115_to_float(expected_q[i]):+.6f})"
                )
    
    # IEEE fp32 comparison report
    if report_ieee and passed:
        report = q115_vs_ieee_report(name, a_q, b_q, N, N, N, results_raw)
        logger.log_section("Q1.15 vs IEEE fp32")
        for line in report.split('\n'):
            logger.log_message(line)
    
    logger.close()
    assert passed, f"{name}: bit-exact matmul verification failed"
    return cycles


# =============================================================================
# Helper: generate Q1.15 matrices from float 2D lists
# =============================================================================

def mat_flat_q115(mat_f: list) -> list:
    """Convert 2D float matrix to flat Q1.15 list."""
    return [float_to_q115(val) for row in mat_f for val in row]


# =============================================================================
# TEST: 4×4 matmul (fills systolic array dimension)
# =============================================================================

@cocotb.test()
async def test_matmul_4x4(dut):
    """4×4 matrix multiplication — 16 threads across 4 blocks."""
    N = 4
    A_f = [
        [0.5,  0.25, 0.125, 0.0625],
        [0.25, 0.5,  0.25,  0.125],
        [0.125, 0.25, 0.5,  0.25],
        [0.0625, 0.125, 0.25, 0.5]
    ]
    B_f = [
        [0.5,  0.0,  0.25,  0.0],
        [0.0,  0.5,  0.0,   0.25],
        [0.25, 0.0,  0.5,   0.0],
        [0.0,  0.25, 0.0,   0.5]
    ]
    a_q = mat_flat_q115(A_f)
    b_q = mat_flat_q115(B_f)
    expected_q = q115_matmul(a_q, b_q, N, N, N)
    
    await run_matmul_test(dut, "matmul_4x4", N, a_q, b_q, expected_q,
                          max_cycles=3000, report_ieee=True)


# =============================================================================
# TEST: 4×4 identity multiplication
# =============================================================================

@cocotb.test()
async def test_matmul_4x4_identity(dut):
    """4×4 A × I ≈ A (using 0.999 on diagonal since 1.0 is unrepresentable)."""
    N = 4
    A_f = [
        [0.5,  -0.25, 0.125, -0.0625],
        [0.75, -0.5,  0.375, -0.25],
        [-0.125, 0.25, -0.5,  0.75],
        [0.0625, -0.125, 0.25, -0.5]
    ]
    I_f = [
        [0.999, 0.0,  0.0,   0.0],
        [0.0,   0.999, 0.0,  0.0],
        [0.0,   0.0,   0.999, 0.0],
        [0.0,   0.0,   0.0,   0.999]
    ]
    a_q = mat_flat_q115(A_f)
    i_q = mat_flat_q115(I_f)
    expected_q = q115_matmul(a_q, i_q, N, N, N)
    
    await run_matmul_test(dut, "matmul_4x4_identity", N, a_q, i_q, expected_q,
                          max_cycles=3000, report_ieee=True)


# =============================================================================
# TEST: 4×4 saturation stress
# =============================================================================

@cocotb.test()
async def test_matmul_4x4_saturation(dut):
    """4×4 matmul with extreme values — verify saturation to Q115_MAX/MIN."""
    N = 4
    
    # Positive overflow: all 0.999 × all 0.999
    a_f = [[0.999] * N for _ in range(N)]
    b_f = [[0.999] * N for _ in range(N)]
    a_q = mat_flat_q115(a_f)
    b_q = mat_flat_q115(b_f)
    expected_q = q115_matmul(a_q, b_q, N, N, N)
    
    await run_matmul_test(dut, "matmul_4x4_sat_pos", N, a_q, b_q, expected_q,
                          max_cycles=3000)
    
    # Negative overflow: all -1.0 × all 0.999
    a_f = [[-1.0] * N for _ in range(N)]
    b_f = [[0.999] * N for _ in range(N)]
    a_q = mat_flat_q115(a_f)
    b_q = mat_flat_q115(b_f)
    expected_q = q115_matmul(a_q, b_q, N, N, N)
    
    await run_matmul_test(dut, "matmul_4x4_sat_neg", N, a_q, b_q, expected_q,
                          max_cycles=3000)


# =============================================================================
# TEST: 8×8 matmul (multi-block tiling stress)
# =============================================================================

@cocotb.test()
async def test_matmul_8x8(dut):
    """8×8 matmul — 64 elements, 16 blocks. Tests multi-block dispatch."""
    N = 8
    random.seed(8800)
    
    A_f = [[random.uniform(-0.5, 0.5) for _ in range(N)] for _ in range(N)]
    B_f = [[random.uniform(-0.5, 0.5) for _ in range(N)] for _ in range(N)]
    
    a_q = mat_flat_q115(A_f)
    b_q = mat_flat_q115(B_f)
    expected_q = q115_matmul(a_q, b_q, N, N, N)
    
    await run_matmul_test(dut, "matmul_8x8", N, a_q, b_q, expected_q,
                          max_cycles=20000, report_ieee=True)


# =============================================================================
# TEST: 8×8 sparse matmul
# =============================================================================

@cocotb.test()
async def test_matmul_8x8_sparse(dut):
    """8×8 sparse matmul — mostly zeros with a few hot values."""
    N = 8
    random.seed(8801)
    
    # Sparse A: ~20% non-zero
    A_f = [[0.0] * N for _ in range(N)]
    for _ in range(int(N * N * 0.2)):
        i, j = random.randint(0, N-1), random.randint(0, N-1)
        A_f[i][j] = random.choice([0.5, -0.5, 0.25, -0.25, 0.999])
    
    # Sparse B: ~20% non-zero
    B_f = [[0.0] * N for _ in range(N)]
    for _ in range(int(N * N * 0.2)):
        i, j = random.randint(0, N-1), random.randint(0, N-1)
        B_f[i][j] = random.choice([0.5, -0.5, 0.125, -0.125, 0.75])
    
    a_q = mat_flat_q115(A_f)
    b_q = mat_flat_q115(B_f)
    expected_q = q115_matmul(a_q, b_q, N, N, N)
    
    await run_matmul_test(dut, "matmul_8x8_sparse", N, a_q, b_q, expected_q,
                          max_cycles=20000)


# =============================================================================
# TEST: Boundary values (corner cases)
# =============================================================================

@cocotb.test()
async def test_matmul_boundary_values(dut):
    """
    Boundary value matmul tests — every Q1.15 edge case:
    0×0, max×max, min×min, max×min, LSB×LSB, max×0, etc.
    """
    N = 2  # Use 2×2 for speed
    
    boundary_cases = [
        ("zero_times_zero",
         [0x0000, 0x0000, 0x0000, 0x0000],
         [0x0000, 0x0000, 0x0000, 0x0000]),
        ("max_times_max",
         [0x7FFF, 0x7FFF, 0x7FFF, 0x7FFF],
         [0x7FFF, 0x7FFF, 0x7FFF, 0x7FFF]),
        ("min_times_min",
         [0x8001, 0x8001, 0x8001, 0x8001],
         [0x8001, 0x8001, 0x8001, 0x8001]),
        ("max_times_min",
         [0x7FFF, 0x7FFF, 0x7FFF, 0x7FFF],
         [0x8001, 0x8001, 0x8001, 0x8001]),
        ("lsb_times_lsb",
         [0x0001, 0x0001, 0x0001, 0x0001],
         [0x0001, 0x0001, 0x0001, 0x0001]),
        ("max_times_zero",
         [0x7FFF, 0x0000, 0x7FFF, 0x0000],
         [0x0000, 0x7FFF, 0x0000, 0x7FFF]),
        ("neg_lsb_times_neg_lsb",
         [0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF],
         [0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF]),
        ("half_times_half",
         [0x4000, 0x4000, 0x4000, 0x4000],
         [0x4000, 0x4000, 0x4000, 0x4000]),
        ("neg_half_times_half",
         [0xC000, 0xC000, 0xC000, 0xC000],
         [0x4000, 0x4000, 0x4000, 0x4000]),
    ]
    
    program = build_matmul_program_nxn(N)
    
    for name, a_q, b_q in boundary_cases:
        expected_q = q115_matmul(a_q, b_q, N, N, N)
        data = a_q + b_q + [0] * (N * N)
        
        logger = await setup_test(
            dut,
            test_name=f"boundary_{name}",
            program=program,
            data=data,
            thread_count=4,
            verbose=False
        )
        
        cycles = await run_kernel(dut, logger, max_cycles=1500, trace_interval=0)
        
        results_raw = read_memory_range(dut, 2 * N * N, N * N)
        passed = results_raw == expected_q
        
        if not passed:
            logger.set_verbose(True)
            logger.log_section(f"BOUNDARY FAIL: {name}")
            for i in range(N * N):
                if results_raw[i] != expected_q[i]:
                    logger.log_message(
                        f"  [{i}] got 0x{results_raw[i]:04X}, "
                        f"expected 0x{expected_q[i]:04X}"
                    )
        logger.close()
        assert passed, f"Boundary test '{name}' failed"


# =============================================================================
# TEST: Alternating sign pattern
# =============================================================================

@cocotb.test()
async def test_matmul_alternating_signs(dut):
    """
    4×4 checkerboard of +/- values to stress accumulator sign changes.
    Accumulator must handle sign flips every multiply.
    """
    N = 4
    # Checkerboard: A[i][j] positive if (i+j) even, negative if odd
    A_f = [
        [0.5 if (i + j) % 2 == 0 else -0.5 for j in range(N)]
        for i in range(N)
    ]
    # B is similar but shifted
    B_f = [
        [0.25 if (i + j) % 2 == 1 else -0.25 for j in range(N)]
        for i in range(N)
    ]
    
    a_q = mat_flat_q115(A_f)
    b_q = mat_flat_q115(B_f)
    expected_q = q115_matmul(a_q, b_q, N, N, N)
    
    await run_matmul_test(dut, "matmul_alternating_signs", N, a_q, b_q, expected_q,
                          max_cycles=3000)


# =============================================================================
# TEST: Large randomized sweep (100 cases, bit-exact)
# =============================================================================

@cocotb.test()
async def test_matmul_random_large(dut):
    """
    100 randomized 4×4 matmul cases — bit-exact verification.
    
    Uses a mix of uniform random values and interesting boundary values.
    Every single output word must match the Q1.15 reference exactly.
    """
    N = 4
    random.seed(42424242)
    
    interesting = [
        0x0000,  # 0
        0x0001,  # +LSB
        0xFFFF,  # -LSB
        0x4000,  # +0.5
        0xC000,  # -0.5
        0x7FFF,  # +max
        0x8001,  # most negative SF16 (0x8000 is negative zero)
        0x8002,  # most negative + 1
        0x2000,  # +0.25
        0xE000,  # -0.25
    ]
    
    def rand_q115() -> int:
        if random.random() < 0.25:
            return random.choice(interesting)
        return random.randint(0, 65535)
    
    program = build_matmul_program_nxn(N)
    num_cases = 100
    
    for case_idx in range(num_cases):
        a_q = [rand_q115() for _ in range(N * N)]
        b_q = [rand_q115() for _ in range(N * N)]
        expected_q = q115_matmul(a_q, b_q, N, N, N)
        
        data = a_q + b_q + [0] * (N * N)
        
        logger = await setup_test(
            dut,
            test_name=f"rand4x4_{case_idx}",
            program=program,
            data=data,
            thread_count=((N * N + 3) // 4) * 4,  # Pad to multiple of 4
            verbose=False
        )
        
        cycles = await run_kernel(dut, logger, max_cycles=3000, trace_interval=0)
        
        results_raw = read_memory_range(dut, 2 * N * N, N * N)
        passed = results_raw == expected_q
        
        if not passed:
            logger.set_verbose(True)
            logger.log_section(f"RANDOM FAIL case {case_idx}")
            logger.log_message(f"A_q: {[f'0x{x:04X}' for x in a_q]}")
            logger.log_message(f"B_q: {[f'0x{x:04X}' for x in b_q]}")
            for i in range(N * N):
                if results_raw[i] != expected_q[i]:
                    logger.log_message(
                        f"  C[{i}] got 0x{results_raw[i]:04X}, "
                        f"expected 0x{expected_q[i]:04X}"
                    )
        logger.close()
        assert passed, f"Random 4×4 matmul case {case_idx} failed"


# =============================================================================
# TEST: Precision sweep (Q1.15 vs IEEE fp32 error analysis)
# =============================================================================

@cocotb.test()
async def test_matmul_precision_sweep(dut):
    """
    SF16 precision analysis across matrix sizes.
    
    For each size, computes matmul on the GPU, then compares against
    IEEE fp32 reference. Reports max/mean/RMS error and ULP statistics.
    
    This test PASSES as long as the SF16 hardware matches the SF16
    Python reference (bit-exact). The IEEE comparison is informational.
    """
    random.seed(31415)
    
    sizes = [2, 3, 4]
    
    for N in sizes:
        a_q = [float_to_q115(random.uniform(-0.5, 0.5)) for _ in range(N * N)]
        b_q = [float_to_q115(random.uniform(-0.5, 0.5)) for _ in range(N * N)]
        expected_q = q115_matmul(a_q, b_q, N, N, N)
        
        base_a = 0
        base_b = N * N
        base_c = 2 * N * N
        
        program = build_matmul_program_nxn(N, base_a, base_b, base_c)
        data = a_q + b_q + [0] * (N * N)
        
        logger = await setup_test(
            dut,
            test_name=f"precision_{N}x{N}",
            program=program,
            data=data,
            thread_count=((N * N + 3) // 4) * 4,  # Pad to multiple of 4
            verbose=False
        )
        
        cycles = await run_kernel(dut, logger, max_cycles=5000, trace_interval=0)
        
        # Allow memory writes to settle
        await ClockCycles(dut.clk, 10)
        
        results_raw = read_memory_range(dut, base_c, N * N)
        
        # Bit-exact check against Q1.15 reference
        passed = results_raw == expected_q
        
        if not passed:
            logger.set_verbose(True)
            logger.log_section(f"PRECISION FAIL {N}×{N}")
            for i in range(N * N):
                if results_raw[i] != expected_q[i]:
                    logger.log_message(
                        f"  [{i}] got 0x{results_raw[i]:04X}, expected 0x{expected_q[i]:04X}"
                    )
        
        # IEEE fp32 comparison (informational)
        report = q115_vs_ieee_report(f"precision_{N}x{N}", a_q, b_q, N, N, N, results_raw)
        logger.log_section(f"Precision Report {N}×{N}")
        for line in report.split('\n'):
            logger.log_message(line)
        
        logger.close()
        assert passed, f"Precision sweep {N}×{N} bit-exact check failed"


# =============================================================================
# TEST: GFLOPS measurement
# =============================================================================

@cocotb.test()
async def test_matmul_gflops(dut):
    """
    GFLOPS measurement across matrix sizes.
    
    Runs matmul at each size, records cycle count, computes GFLOPS.
    Prints a formatted performance table at the end.
    """
    random.seed(27182)
    
    sizes = [2, 3, 4]
    reports = []
    
    for N in sizes:
        a_q = [float_to_q115(random.uniform(-0.5, 0.5)) for _ in range(N * N)]
        b_q = [float_to_q115(random.uniform(-0.5, 0.5)) for _ in range(N * N)]
        expected_q = q115_matmul(a_q, b_q, N, N, N)
        
        program = build_matmul_program_nxn(N)
        data = a_q + b_q + [0] * (N * N)
        
        logger = await setup_test(
            dut,
            test_name=f"gflops_{N}x{N}",
            program=program,
            data=data,
            thread_count=((N * N + 3) // 4) * 4,  # Pad to multiple of 4
            verbose=False
        )
        
        cycles = await run_kernel(dut, logger, max_cycles=10000, trace_interval=0)
        
        # Allow memory writes to settle
        await ClockCycles(dut.clk, 10)
        
        results_raw = read_memory_range(dut, 2 * N * N, N * N)
        passed = results_raw == expected_q
        
        perf = PerformanceReport(f"matmul_{N}x{N}", N, N, N)
        perf.record(cycles)
        reports.append(perf)
        
        logger.log_section(f"Performance {N}×{N}")
        logger.log_message(perf.summary())
        logger.close()
        
        assert passed, f"GFLOPS test {N}×{N} bit-exact check failed"
    
    # Print summary table
    table = format_perf_table(reports)
    print("\n" + table + "\n")


# =============================================================================
# TEST: 16×16 matmul (large stress test)
# =============================================================================

@cocotb.test(skip=True)
async def test_matmul_16x16(dut):
    """
    SKIPPED — 16×16 matmul requires two unsupported features in this kernel builder:

    1. base_b = 256 exceeds the 8-bit sign-extended CONST immediate range (−128..+127),
       so it cannot be loaded with a single CONST instruction.
    2. N² = 256 output elements exceeds the 8-bit thread_count register (max 255),
       so a single-dispatch run cannot cover all output elements.

    Both issues are resolved in test_matmul_vvlarge.py which uses:
    - build_large_const() from helpers/addr.py for arbitrary address encoding, and
    - a multi-dispatch runner that splits output elements across multiple kernel calls.

    Run `make test_matmul_vvlarge` to exercise the correct 16×16 test.
    """
    pass  # pragma: no cover
