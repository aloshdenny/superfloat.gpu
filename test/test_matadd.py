"""
Matrix Addition Test for Atreides GPU

Tests element-wise addition of two 1x8 matrices using Q1.15 arithmetic.
Each thread computes: C[i] = A[i] + B[i]

Memory layout:
  0-7:   Matrix A (8 elements)
  8-15:  Matrix B (8 elements)
  16-23: Matrix C (results)
"""

import cocotb
from cocotb.triggers import ClockCycles

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from helpers.q115 import float_to_q115, q115_to_float, q115_add, q115_vector_add
from helpers.memory import (
    init_data_memory, init_program_memory, read_memory_range, dump_memory,
    asm_mul, asm_add, asm_const, asm_ldr, asm_str, asm_act, asm_ret,
    R0, R1, R2, R3, R4, R5, R6, R7, BLOCK_IDX, BLOCK_DIM, THREAD_IDX
)
from helpers.setup import setup_test, run_kernel


Q115_MAX = 0x7FFF
Q115_MIN = 0x8000

# Test data: A = [0.25] * 8, B = [0.5] * 8 => C = [0.75] * 8
TEST_A = [0.25] * 8
TEST_B = [0.5] * 8
EXPECTED_Q = q115_vector_add([float_to_q115(a) for a in TEST_A], [float_to_q115(b) for b in TEST_B])
EXPECTED_C = [q115_to_float(x) for x in EXPECTED_Q]


def build_matadd_program():
    """
    Build the matrix addition kernel.
    
    Assembly:
        MUL R0, %blockIdx, %blockDim    ; i = blockIdx * blockDim
        ADD R0, R0, %threadIdx          ; i += threadIdx
        
        CONST R1, #0                    ; baseA = 0
        CONST R2, #8                    ; baseB = 8
        CONST R3, #16                   ; baseC = 16
        
        ADD R4, R1, R0                  ; addr_A = baseA + i
        LDR R4, R4                      ; R4 = A[i]
        
        ADD R5, R2, R0                  ; addr_B = baseB + i
        LDR R5, R5                      ; R5 = B[i]
        
        ACT R4, R4, R5                  ; R4 = sat_q115(A[i] + B[i])  (ACT_NONE via Rd=R4)
        
        ADD R7, R3, R0                  ; addr_C = baseC + i
        STR R7, R4                      ; C[i] = R4
        
        RET
    """
    return [
        asm_mul(R0, BLOCK_IDX, BLOCK_DIM),   # 0: i = blockIdx * blockDim
        asm_add(R0, R0, THREAD_IDX),          # 1: i += threadIdx
        
        asm_const(R1, 0),                     # 2: baseA = 0
        asm_const(R2, 8),                     # 3: baseB = 8
        asm_const(R3, 16),                    # 4: baseC = 16
        
        asm_add(R4, R1, R0),                  # 5: addr_A = baseA + i
        asm_ldr(R4, R4),                      # 6: R4 = A[i]
        
        asm_add(R5, R2, R0),                  # 7: addr_B = baseB + i
        asm_ldr(R5, R5),                      # 8: R5 = B[i]
        
        asm_act(R4, R4, R5),                  # 9: R4 = sat_q115(A[i] + B[i])
        
        asm_add(R7, R3, R0),                  # 10: addr_C = baseC + i
        asm_str(R7, R4),                      # 11: C[i] = R4
        
        asm_ret(),                            # 12: return
    ]


def build_initial_data():
    """Build initial data memory contents."""
    data = []
    
    # Matrix A (addresses 0-7)
    for val in TEST_A:
        data.append(float_to_q115(val))
    
    # Matrix B (addresses 8-15)
    for val in TEST_B:
        data.append(float_to_q115(val))
    
    # Matrix C (addresses 16-23) - initialized to 0
    data.extend([0] * 8)
    
    return data


@cocotb.test()
async def test_matadd(dut):
    """
    Test matrix addition kernel.
    
    Launches 8 threads to add two 1x8 matrices element-wise.
    """
    # Build program and data
    program = build_matadd_program()
    data = build_initial_data()
    
    # Setup test
    logger = await setup_test(
        dut,
        test_name="matadd",
        program=program,
        data=data,
        thread_count=8,
        verbose=True
    )
    
    # Run kernel
    cycles = await run_kernel(dut, logger, max_cycles=500, trace_interval=10)
    
    # Read results
    logger.log_section("Results")
    
    results_raw = read_memory_range(dut, 16, 8)
    results = [q115_to_float(r) for r in results_raw]
    
    logger.log_message("Result matrix C (Q1.15 hex):")
    logger.log_message(f"  {' '.join(f'{r:04X}' for r in results_raw)}")
    
    logger.log_message("Result matrix C (float):")
    logger.log_message(f"  {results}")
    
    logger.log_message("Expected:")
    logger.log_message(f"  {EXPECTED_C}")
    
    # Dump final memory state
    logger.log_section("Final Memory State")
    final_memory = dump_memory(dut, 0, 32)
    logger.log_memory(final_memory, 0, 32, "Data Memory")
    
    # Verify results
    passed = True
    tolerance = 0.001  # Allow small floating point tolerance
    
    for i, (actual, expected) in enumerate(zip(results, EXPECTED_C)):
        if abs(actual - expected) > tolerance:
            logger.log_message(f"MISMATCH at index {i}: got {actual}, expected {expected}")
            passed = False
    
    logger.log_result(passed, EXPECTED_C, results)
    logger.close()
    
    assert passed, f"Matrix addition failed. Expected {EXPECTED_C}, got {results}"


@cocotb.test()
async def test_matadd_negative(dut):
    """
    Test matrix addition with negative Q1.15 values.
    """
    # Test with negative values
    test_a = [-0.5, 0.25, -0.125, 0.75, -0.375, 0.0, -1.0, 0.5]
    test_b = [0.25, -0.25, 0.125, -0.25, 0.125, 0.5, 0.5, -0.5]
    expected_q = [
        q115_add(float_to_q115(a), float_to_q115(b)) for a, b in zip(test_a, test_b)
    ]
    expected = [q115_to_float(x) for x in expected_q]
    
    # Build data
    data = []
    for val in test_a:
        data.append(float_to_q115(val))
    for val in test_b:
        data.append(float_to_q115(val))
    data.extend([0] * 8)
    
    program = build_matadd_program()
    
    # Setup test
    logger = await setup_test(
        dut,
        test_name="matadd_negative",
        program=program,
        data=data,
        thread_count=8,
        verbose=True
    )
    
    # Run kernel
    await run_kernel(dut, logger, max_cycles=500, trace_interval=0)
    
    # Read and verify results
    results_raw = read_memory_range(dut, 16, 8)
    results = [q115_to_float(r) for r in results_raw]
    
    logger.log_section("Results")
    logger.log_message(f"Expected: {expected}")
    logger.log_message(f"Actual:   {results}")
    
    passed = True
    tolerance = 0.001
    for i, (actual, exp) in enumerate(zip(results, expected)):
        if abs(actual - exp) > tolerance:
            logger.log_message(f"MISMATCH at index {i}: got {actual}, expected {exp}")
            passed = False
    
    logger.log_result(passed, expected, results)
    logger.close()
    
    assert passed, f"Matrix addition (negative) failed"


@cocotb.test()
async def test_matadd_saturation(dut):
    """Test matadd saturates on overflow/underflow."""
    # Two cases: positive overflow and negative underflow
    cases = [
        ("matadd_sat_pos", [0.999] * 8, [0.999] * 8, Q115_MAX),
        ("matadd_sat_neg", [-1.0] * 8, [-0.75] * 8, Q115_MIN),
    ]

    program = build_matadd_program()

    for name, vec_a, vec_b, expected_sat in cases:
        data = [float_to_q115(v) for v in vec_a] + [float_to_q115(v) for v in vec_b] + ([0] * 8)

        logger = await setup_test(
            dut,
            test_name=name,
            program=program,
            data=data,
            thread_count=8,
            verbose=True
        )

        await run_kernel(dut, logger, max_cycles=800, trace_interval=0)

        results_raw = read_memory_range(dut, 16, 8)
        passed = all(r == expected_sat for r in results_raw)

        logger.log_section("Results")
        logger.log_message(f"Expected saturated: 0x{expected_sat:04X}")
        logger.log_message(f"Actual:            {' '.join(f'{r:04X}' for r in results_raw)}")
        logger.log_result(passed, [expected_sat] * 8, results_raw)
        logger.close()

        assert passed, f"{name} failed"


@cocotb.test()
async def test_matadd_random_q115(dut):
    """Randomized Q1.15 matadd vs Python reference (with saturation)."""
    import random

    random.seed(1234)
    program = build_matadd_program()

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
        vec_a_q = [rand_q115() for _ in range(8)]
        vec_b_q = [rand_q115() for _ in range(8)]
        expected_q = q115_vector_add(vec_a_q, vec_b_q)

        data = vec_a_q + vec_b_q + ([0] * 8)

        logger = await setup_test(
            dut,
            test_name=f"matadd_rand_{case_idx}",
            program=program,
            data=data,
            thread_count=8,
            verbose=False
        )

        await run_kernel(dut, logger, max_cycles=800, trace_interval=0)

        results_raw = read_memory_range(dut, 16, 8)
        passed = results_raw == expected_q
        if not passed:
            logger.set_verbose(True)
            logger.log_section("Mismatch")
            logger.log_message(f"A: {' '.join(f'{x:04X}' for x in vec_a_q)}")
            logger.log_message(f"B: {' '.join(f'{x:04X}' for x in vec_b_q)}")
            logger.log_message(f"Expected: {' '.join(f'{x:04X}' for x in expected_q)}")
            logger.log_message(f"Actual:   {' '.join(f'{x:04X}' for x in results_raw)}")
        logger.close()

        assert passed, f"Random matadd case {case_idx} failed"
