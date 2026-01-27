"""
Matrix Multiplication Test for Atreides GPU

Tests 2x2 matrix multiplication using Q1.15 FMA operations.
Each thread computes one element of C = A × B.

Thread mapping:
  Thread 0: C[0][0] = A[0][0]*B[0][0] + A[0][1]*B[1][0]
  Thread 1: C[0][1] = A[0][0]*B[0][1] + A[0][1]*B[1][1]
  Thread 2: C[1][0] = A[1][0]*B[0][0] + A[1][1]*B[1][0]
  Thread 3: C[1][1] = A[1][0]*B[0][1] + A[1][1]*B[1][1]

Memory layout (row-major):
  0-3:  Matrix A (2x2)
  4-7:  Matrix B (2x2)
  8-11: Matrix C (results)
"""

import cocotb
from cocotb.triggers import ClockCycles

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from helpers.q115 import float_to_q115, q115_to_float, q115_matmul
from helpers.memory import (
    init_data_memory, init_program_memory, read_memory_range, dump_memory,
    asm_mul, asm_add, asm_sub, asm_div, asm_const, asm_ldr, asm_str, asm_fma,
    asm_cmp, asm_brn, asm_ret,
    R0, R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, BLOCK_IDX, BLOCK_DIM, THREAD_IDX
)
from helpers.setup import setup_test, run_kernel


# Test data: 2x2 matrices with Q1.15 values
# A = [[0.5, 0.25], [0.125, 0.5]]
# B = [[0.5, 0.25], [0.25, 0.5]]
TEST_A = [
    [0.5, 0.25],
    [0.125, 0.5]
]
TEST_B = [
    [0.5, 0.25],
    [0.25, 0.5]
]

def mat_to_flat_q115(mat_f_2x2: list) -> list:
    return [float_to_q115(mat_f_2x2[r][c]) for r in range(2) for c in range(2)]


EXPECTED_Q = q115_matmul(mat_to_flat_q115(TEST_A), mat_to_flat_q115(TEST_B), 2, 2, 2)
EXPECTED_C = [q115_to_float(x) for x in EXPECTED_Q]


def expected_matmul_q115(A_f: list, B_f: list) -> list:
    """Compute expected 2x2 matmul using the Python Q1.15 reference implementation."""
    return q115_matmul(mat_to_flat_q115(A_f), mat_to_flat_q115(B_f), 2, 2, 2)



def build_matmul_program():
    """
    Build the matrix multiplication kernel.
    
    Each thread computes C[row][col] where:
      row = i / N
      col = i % N
      C[row][col] = sum(A[row][k] * B[k][col] for k in 0..N-1)
    
    Assembly:
        ; Calculate global thread index
        MUL R0, %blockIdx, %blockDim    ; i = blockIdx * blockDim
        ADD R0, R0, %threadIdx          ; i += threadIdx
        
        ; Constants
        CONST R1, #1                    ; increment
        CONST R2, #2                    ; N (matrix dimension)
        CONST R3, #0                    ; baseA
        CONST R4, #4                    ; baseB
        CONST R5, #8                    ; baseC
        
        ; Calculate row and col
        DIV R6, R0, R2                  ; row = i / N
        MUL R7, R6, R2                  ; row * N
        SUB R7, R0, R7                  ; col = i - row * N = i % N
        
        ; Initialize accumulator and loop counter
        CONST R8, #0                    ; acc = 0 (Q1.15)
        CONST R9, #0                    ; k = 0
        
    LOOP:
        ; Load A[row][k]
        MUL R10, R6, R2                 ; row * N
        ADD R10, R10, R9                ; row * N + k
        ADD R10, R10, R3                ; + baseA
        LDR R10, R10                    ; R10 = A[row][k]
        
        ; Load B[k][col]
        MUL R11, R9, R2                 ; k * N
        ADD R11, R11, R7                ; k * N + col
        ADD R11, R11, R4                ; + baseB
        LDR R11, R11                    ; R11 = B[k][col]
        
        ; FMA: acc += A[row][k] * B[k][col]
        FMA R8, R10, R11                ; R8 = (R10 * R11) + R8
        
        ; k++
        ADD R9, R9, R1
        
        ; Loop while k < N
        CMP R9, R2
        BRn LOOP                        ; branch if R9 < R2 (negative result)
        
        ; Store result
        ADD R9, R5, R0                  ; addr_C = baseC + i
        STR R9, R8                      ; C[i] = acc
        
        RET
    """
    return [
        # 0-1: Calculate global thread index
        asm_mul(R0, BLOCK_IDX, BLOCK_DIM),   # 0: i = blockIdx * blockDim
        asm_add(R0, R0, THREAD_IDX),          # 1: i += threadIdx
        
        # 2-6: Constants
        asm_const(R1, 1),                     # 2: increment = 1
        asm_const(R2, 2),                     # 3: N = 2
        asm_const(R3, 0),                     # 4: baseA = 0
        asm_const(R4, 4),                     # 5: baseB = 4
        asm_const(R5, 8),                     # 6: baseC = 8
        
        # 7-9: Calculate row and col
        asm_div(R6, R0, R2),                  # 7: row = i / N
        asm_mul(R7, R6, R2),                  # 8: row * N
        asm_sub(R7, R0, R7),                  # 9: col = i % N
        
        # 10-11: Initialize accumulator and loop counter
        asm_const(R8, 0),                     # 10: acc = 0
        asm_const(R9, 0),                     # 11: k = 0
        
        # LOOP (starting at instruction 12):
        # 12-15: Load A[row][k]
        asm_mul(R10, R6, R2),                 # 12: row * N
        asm_add(R10, R10, R9),                # 13: + k
        asm_add(R10, R10, R3),                # 14: + baseA
        asm_ldr(R10, R10),                    # 15: R10 = A[row][k]
        
        # 16-19: Load B[k][col]
        asm_mul(R11, R9, R2),                 # 16: k * N
        asm_add(R11, R11, R7),                # 17: + col
        asm_add(R11, R11, R4),                # 18: + baseB
        asm_ldr(R11, R11),                    # 19: R11 = B[k][col]
        
        # 20: FMA
        asm_fma(R8, R10, R11),                # 20: acc += A[row][k] * B[k][col]
        
        # 21-23: Loop control
        asm_add(R9, R9, R1),                  # 21: k++
        asm_cmp(R9, R2),                      # 22: compare k with N
        asm_brn(12 - 24),                     # 23: branch to LOOP if negative (k < N)
                                              #     offset = 12 - 24 = -12 (relative to PC+1=24)
        
        # 24-25: Store result
        asm_add(R9, R5, R0),                  # 24: addr_C = baseC + i
        asm_str(R9, R8),                      # 25: C[i] = acc
        
        # 26: Return
        asm_ret(),                            # 26: done
    ]


def build_initial_data():
    """Build initial data memory contents."""
    data = []
    
    # Matrix A (addresses 0-3, row-major)
    for row in TEST_A:
        for val in row:
            data.append(float_to_q115(val))
    
    # Matrix B (addresses 4-7, row-major)
    for row in TEST_B:
        for val in row:
            data.append(float_to_q115(val))
    
    # Matrix C (addresses 8-11) - initialized to 0
    data.extend([0] * 4)
    
    return data


@cocotb.test()
async def test_matmul(dut):
    """
    Test 2x2 matrix multiplication kernel.
    
    Launches 4 threads to compute C = A × B using FMA operations.
    """
    # Build program and data
    program = build_matmul_program()
    data = build_initial_data()
    
    # Setup test
    logger = await setup_test(
        dut,
        test_name="matmul",
        program=program,
        data=data,
        thread_count=4,
        verbose=True
    )
    
    # Log initial memory
    logger.log_section("Initial Memory")
    logger.log_message("Matrix A (Q1.15):")
    for i in range(2):
        row = [f"{data[i*2+j]:04X}" for j in range(2)]
        logger.log_message(f"  [{', '.join(row)}]")
    
    logger.log_message("Matrix B (Q1.15):")
    for i in range(2):
        row = [f"{data[4+i*2+j]:04X}" for j in range(2)]
        logger.log_message(f"  [{', '.join(row)}]")
    
    # Run kernel
    cycles = await run_kernel(dut, logger, max_cycles=1000, trace_interval=10)
    
    # Read results
    logger.log_section("Results")
    
    results_raw = read_memory_range(dut, 8, 4)
    results = [q115_to_float(r) for r in results_raw]
    
    logger.log_message("Result matrix C (Q1.15 hex):")
    for i in range(2):
        row = [f"{results_raw[i*2+j]:04X}" for j in range(2)]
        logger.log_message(f"  [{', '.join(row)}]")
    
    logger.log_message("Result matrix C (float):")
    for i in range(2):
        row = [f"{results[i*2+j]:.6f}" for j in range(2)]
        logger.log_message(f"  [{', '.join(row)}]")
    
    logger.log_message("Expected matrix C (float):")
    for i in range(2):
        row = [f"{EXPECTED_C[i*2+j]:.6f}" for j in range(2)]
        logger.log_message(f"  [{', '.join(row)}]")
    
    # Dump final memory state
    logger.log_section("Final Memory State")
    final_memory = dump_memory(dut, 0, 16)
    logger.log_memory(final_memory, 0, 16, "Data Memory")
    
    # Verify results
    passed = results_raw == EXPECTED_Q
    if not passed:
        for i, (actual, expected) in enumerate(zip(results_raw, EXPECTED_Q)):
            if actual != expected:
                row, col = i // 2, i % 2
                logger.log_message(f"MISMATCH at C[{row}][{col}]: got 0x{actual:04X}, expected 0x{expected:04X}")
    
    logger.log_result(passed, EXPECTED_C, results)
    logger.close()
    
    assert passed, f"Matrix multiplication failed"


@cocotb.test()
async def test_matmul_identity(dut):
    """
    Test matrix multiplication with identity matrix.
    A × I = A
    """
    # A = [[0.5, 0.25], [0.125, 0.75]]
    # I = [[1.0, 0], [0, 1.0]] (but we'll use 0.999... for Q1.15 max)
    # Note: Q1.15 can't represent exactly 1.0, so we use the maximum representable value
    
    test_a = [[0.5, 0.25], [0.125, 0.75]]
    # For identity, we use values close to 1 and 0
    test_i = [[0.999, 0.0], [0.0, 0.999]]
    
    expected_q = expected_matmul_q115(test_a, test_i)
    expected = [q115_to_float(x) for x in expected_q]
    
    # Build data
    data = []
    for row in test_a:
        for val in row:
            data.append(float_to_q115(val))
    for row in test_i:
        for val in row:
            data.append(float_to_q115(val))
    data.extend([0] * 4)
    
    program = build_matmul_program()
    
    # Setup test
    logger = await setup_test(
        dut,
        test_name="matmul_identity",
        program=program,
        data=data,
        thread_count=4,
        verbose=True
    )
    
    # Run kernel
    await run_kernel(dut, logger, max_cycles=1000, trace_interval=0)
    
    # Read and verify results
    results_raw = read_memory_range(dut, 8, 4)
    results = [q115_to_float(r) for r in results_raw]
    
    logger.log_section("Results")
    logger.log_message(f"Expected (A × I ≈ A): {expected}")
    logger.log_message(f"Actual:               {results}")
    
    passed = results_raw == expected_q
    if not passed:
        for i, (actual, expected_word) in enumerate(zip(results_raw, expected_q)):
            if actual != expected_word:
                logger.log_message(f"MISMATCH at index {i}: got 0x{actual:04X}, expected 0x{expected_word:04X}")
    
    logger.log_result(passed, expected, results)
    logger.close()
    
    assert passed, f"Matrix multiplication (identity) failed"


@cocotb.test()
async def test_matmul_saturation(dut):
    """Force overflow/underflow in Q1.15 matmul and check saturation."""
    cases = [
        ("matmul_sat_pos", [[0.999, 0.999], [0.999, 0.999]], [[0.999, 0.999], [0.999, 0.999]]),
        ("matmul_sat_neg", [[-1.0, -1.0], [-1.0, -1.0]], [[0.999, 0.999], [0.999, 0.999]]),
    ]

    program = build_matmul_program()

    for name, a_f, b_f in cases:
        data = []
        for row in a_f:
            for v in row:
                data.append(float_to_q115(v))
        for row in b_f:
            for v in row:
                data.append(float_to_q115(v))
        data.extend([0] * 4)

        expected_q = expected_matmul_q115(a_f, b_f)

        logger = await setup_test(
            dut,
            test_name=name,
            program=program,
            data=data,
            thread_count=4,
            verbose=True
        )

        await run_kernel(dut, logger, max_cycles=1200, trace_interval=0)

        results_raw = read_memory_range(dut, 8, 4)
        passed = results_raw == expected_q

        logger.log_section("Results")
        logger.log_message(f"Expected: {' '.join(f'{x:04X}' for x in expected_q)}")
        logger.log_message(f"Actual:   {' '.join(f'{x:04X}' for x in results_raw)}")
        logger.log_result(passed, [q115_to_float(x) for x in expected_q], [q115_to_float(x) for x in results_raw])
        logger.close()

        assert passed, f"{name} failed"


@cocotb.test()
async def test_matmul_random_q115(dut):
    """Randomized Q1.15 matmul vs Python reference (with saturation)."""
    import random

    random.seed(5678)
    program = build_matmul_program()

    interesting = [
        0x0000,  # 0
        0x0001,  # +LSB
        0xFFFF,  # -LSB
        0x4000,  # +0.5
        0xC000,  # -0.5
        0x7FFF,  # +max
        0x7FDF,  # ~0.999
        0x8000,  # -1.0
        0x8001,  # -1.0 + LSB
    ]

    def rand_q115() -> int:
        if random.random() < 0.35:
            return random.choice(interesting)
        signed = random.randint(-32768, 32767)
        return signed & 0xFFFF

    num_cases = 25
    for case_idx in range(num_cases):
        a_q = [rand_q115() for _ in range(4)]
        b_q = [rand_q115() for _ in range(4)]
        expected_q = q115_matmul(a_q, b_q, 2, 2, 2)

        data = a_q + b_q + ([0] * 4)

        logger = await setup_test(
            dut,
            test_name=f"matmul_rand_{case_idx}",
            program=program,
            data=data,
            thread_count=4,
            verbose=False
        )

        await run_kernel(dut, logger, max_cycles=1200, trace_interval=0)

        results_raw = read_memory_range(dut, 8, 4)
        passed = results_raw == expected_q
        if not passed:
            logger.set_verbose(True)
            logger.log_section("Mismatch")
            logger.log_message(f"Expected: {' '.join(f'{x:04X}' for x in expected_q)}")
            logger.log_message(f"Actual:   {' '.join(f'{x:04X}' for x in results_raw)}")
        logger.close()

        assert passed, f"Random matmul case {case_idx} failed"
