"""
FMA Unit Tests for Atreides GPU

Tests the Q1.15 Fused Multiply-Add unit with comprehensive test cases:
- Basic multiplication
- Accumulation
- Saturation handling
- Edge cases (zero, max, min)
- Sign combinations
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer
import random
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from helpers.q115 import float_to_q115, q115_to_float, q115_mul, q115_add, q115_fma
from helpers.logger import GPULogger


# Core states from the design
STATE_IDLE = 0b000
STATE_FETCH = 0b001
STATE_DECODE = 0b010
STATE_REQUEST = 0b011
STATE_WAIT = 0b100
STATE_EXECUTE = 0b101
STATE_UPDATE = 0b110


async def setup_fma_test(dut, test_name: str, clock_period_ns: int = 10) -> GPULogger:
    """Set up FMA unit test environment."""
    logger = GPULogger(test_name, log_dir="test/results")
    logger.set_verbose(True)
    
    logger.log_section(f"FMA Unit Test: {test_name}")
    
    # Start clock
    clock = Clock(dut.clk, clock_period_ns, units="ns")
    cocotb.start_soon(clock.start())
    
    # Initialize signals
    dut.reset.value = 1
    dut.enable.value = 0
    dut.core_state.value = STATE_IDLE
    dut.fma_enable.value = 0
    dut.rs.value = 0
    dut.rt.value = 0
    dut.rq.value = 0
    
    # Wait for reset
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    dut.enable.value = 1
    await ClockCycles(dut.clk, 2)
    
    return logger


async def execute_fma(dut, rs: int, rt: int, rq: int) -> int:
    """
    Execute a single FMA operation: result = (rs * rt) + rq
    
    The FMA has a 2-stage pipeline:
    - Stage 1: Multiply (rs * rt) -> r3_weighted
    - Stage 2: Accumulate (r3_weighted + rq) -> fma_out
    
    Args:
        dut: Device under test
        rs: Activation value (Q1.15)
        rt: Weight value (Q1.15)
        rq: Accumulator value (Q1.15)
        
    Returns:
        FMA result (Q1.15)
    """
    # Load inputs in REQUEST state
    dut.core_state.value = STATE_REQUEST
    dut.rs.value = rs
    dut.rt.value = rt
    dut.rq.value = rq
    await RisingEdge(dut.clk)
    
    # Execute cycle 1: Multiply stage - r3_weighted gets product
    dut.core_state.value = STATE_EXECUTE
    dut.fma_enable.value = 1
    await RisingEdge(dut.clk)
    
    # Execute cycle 2: Accumulate stage - fma_out gets (r3_weighted + rq)
    # Need to keep in EXECUTE state for the accumulation to use the new r3
    await RisingEdge(dut.clk)
    
    # Execute cycle 3: Result is now valid
    await RisingEdge(dut.clk)
    
    # Read result
    dut.fma_enable.value = 0
    dut.core_state.value = STATE_IDLE
    
    result = int(dut.fma_out.value)
    return result


def format_q115(val: int) -> str:
    """Format Q1.15 value as hex and float."""
    return f"0x{val:04X} ({q115_to_float(val):+.6f})"


@cocotb.test()
async def test_fma_basic_multiply(dut):
    """Test basic Q1.15 multiplication through FMA with zero accumulator."""
    logger = await setup_fma_test(dut, "fma_basic_multiply")
    
    test_cases = [
        # (rs, rt, description)
        (0.5, 0.5, "0.5 * 0.5 = 0.25"),
        (0.25, 0.5, "0.25 * 0.5 = 0.125"),
        (-0.5, 0.5, "-0.5 * 0.5 = -0.25"),
        (0.5, -0.5, "0.5 * -0.5 = -0.25"),
        (-0.5, -0.5, "-0.5 * -0.5 = 0.25"),
        (0.125, 0.125, "0.125 * 0.125 = 0.015625"),
        (0.999, 0.5, "~1.0 * 0.5 = ~0.5"),
    ]
    
    passed = True
    results = []
    
    for rs_f, rt_f, desc in test_cases:
        rs_q = float_to_q115(rs_f)
        rt_q = float_to_q115(rt_f)
        rq_q = 0  # Zero accumulator
        
        # Execute FMA
        hw_result = await execute_fma(dut, rs_q, rt_q, rq_q)
        
        # Compute expected using Python reference
        expected = q115_fma(rq_q, rs_q, rt_q)
        
        hw_float = q115_to_float(hw_result)
        exp_float = q115_to_float(expected)
        
        match = hw_result == expected
        if not match:
            passed = False
        
        status = "PASS" if match else "FAIL"
        logger.log_message(f"  {desc}")
        logger.log_message(f"    RS={format_q115(rs_q)}, RT={format_q115(rt_q)}")
        logger.log_message(f"    HW={format_q115(hw_result)}, Expected={format_q115(expected)} [{status}]")
        
        results.append((desc, hw_result, expected, match))
    
    logger.log_result(passed, [r[2] for r in results], [r[1] for r in results])
    logger.close()
    
    assert passed, "FMA basic multiply test failed"


@cocotb.test()
async def test_fma_accumulate(dut):
    """Test FMA accumulation: result = (rs * rt) + rq."""
    logger = await setup_fma_test(dut, "fma_accumulate")
    
    test_cases = [
        # (rs, rt, rq, description)
        (0.5, 0.5, 0.125, "0.5*0.5 + 0.125 = 0.375"),
        (0.25, 0.5, 0.25, "0.25*0.5 + 0.25 = 0.375"),
        (-0.5, 0.5, 0.5, "-0.5*0.5 + 0.5 = 0.25"),
        (0.5, 0.5, -0.125, "0.5*0.5 - 0.125 = 0.125"),
        (0.1, 0.2, 0.3, "0.1*0.2 + 0.3 = 0.32"),
    ]
    
    passed = True
    
    for rs_f, rt_f, rq_f, desc in test_cases:
        rs_q = float_to_q115(rs_f)
        rt_q = float_to_q115(rt_f)
        rq_q = float_to_q115(rq_f)
        
        hw_result = await execute_fma(dut, rs_q, rt_q, rq_q)
        expected = q115_fma(rq_q, rs_q, rt_q)
        
        match = hw_result == expected
        if not match:
            passed = False
        
        status = "PASS" if match else "FAIL"
        logger.log_message(f"  {desc}")
        logger.log_message(f"    RS={format_q115(rs_q)}, RT={format_q115(rt_q)}, RQ={format_q115(rq_q)}")
        logger.log_message(f"    HW={format_q115(hw_result)}, Expected={format_q115(expected)} [{status}]")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "FMA accumulate test failed"


@cocotb.test()
async def test_fma_saturation(dut):
    """Test FMA saturation at Q1.15 boundaries."""
    logger = await setup_fma_test(dut, "fma_saturation")
    
    Q115_MAX = 0x7FFF  # +0.99997
    Q115_MIN = 0x8000  # -1.0
    
    test_cases = [
        # (rs, rt, rq, expected_saturated, description)
        (Q115_MAX, Q115_MAX, Q115_MAX, True, "Max * Max + Max -> saturate positive"),
        (Q115_MIN, Q115_MAX, Q115_MIN, True, "Min * Max + Min -> saturate negative"),
        (0x4000, 0x4000, 0x7000, True, "0.5 * 0.5 + 0.875 -> near saturation"),
    ]
    
    passed = True
    
    for rs_q, rt_q, rq_q, expect_sat, desc in test_cases:
        hw_result = await execute_fma(dut, rs_q, rt_q, rq_q)
        expected = q115_fma(rq_q, rs_q, rt_q)
        
        # Check if result is at saturation boundary
        is_saturated = (hw_result == Q115_MAX) or (hw_result == Q115_MIN)
        
        match = hw_result == expected
        if not match:
            passed = False
        
        status = "PASS" if match else "FAIL"
        logger.log_message(f"  {desc}")
        logger.log_message(f"    RS={format_q115(rs_q)}, RT={format_q115(rt_q)}, RQ={format_q115(rq_q)}")
        logger.log_message(f"    HW={format_q115(hw_result)}, Expected={format_q115(expected)}")
        logger.log_message(f"    Saturated: {is_saturated} [{status}]")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "FMA saturation test failed"


def q115_close(a: int, b: int, tolerance: int = 1) -> bool:
    """Check if two Q1.15 values are within tolerance (LSBs)."""
    # Handle signed comparison
    a_signed = a if a < 32768 else a - 65536
    b_signed = b if b < 32768 else b - 65536
    return abs(a_signed - b_signed) <= tolerance


@cocotb.test()
async def test_fma_edge_cases(dut):
    """Test FMA edge cases: zero, identity, extremes."""
    logger = await setup_fma_test(dut, "fma_edge_cases")
    
    Q115_MAX = 0x7FFF
    Q115_MIN = 0x8000
    ZERO = 0x0000
    
    test_cases = [
        # (rs, rt, rq, description)
        (ZERO, 0x4000, 0x2000, "0 * x + y = y"),
        (0x4000, ZERO, 0x2000, "x * 0 + y = y"),
        (0x4000, 0x4000, ZERO, "x * y + 0 = x*y"),
        (ZERO, ZERO, ZERO, "0 * 0 + 0 = 0"),
        (Q115_MAX, 0x0001, ZERO, "Max * tiny = small positive"),
        (Q115_MIN, 0x0001, ZERO, "Min * tiny = small negative"),
    ]
    
    passed = True
    
    for rs_q, rt_q, rq_q, desc in test_cases:
        hw_result = await execute_fma(dut, rs_q, rt_q, rq_q)
        expected = q115_fma(rq_q, rs_q, rt_q)
        
        # Allow 1 LSB tolerance for truncation vs rounding differences
        match = q115_close(hw_result, expected, tolerance=1)
        if not match:
            passed = False
        
        status = "PASS" if match else "FAIL"
        logger.log_message(f"  {desc}")
        logger.log_message(f"    HW={format_q115(hw_result)}, Expected={format_q115(expected)} [{status}]")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "FMA edge cases test failed"


@cocotb.test()
async def test_fma_random_values(dut):
    """Test FMA with random Q1.15 values."""
    logger = await setup_fma_test(dut, "fma_random")
    
    random.seed(42)  # Reproducible results
    num_tests = 50
    
    passed = True
    mismatches = 0
    
    logger.log_message(f"Running {num_tests} random FMA operations...")
    logger.log_message("(Allowing 1 LSB tolerance for truncation vs rounding)")
    
    for i in range(num_tests):
        # Generate random Q1.15 values
        rs_f = random.uniform(-1.0, 0.999)
        rt_f = random.uniform(-1.0, 0.999)
        rq_f = random.uniform(-1.0, 0.999)
        
        rs_q = float_to_q115(rs_f)
        rt_q = float_to_q115(rt_f)
        rq_q = float_to_q115(rq_f)
        
        hw_result = await execute_fma(dut, rs_q, rt_q, rq_q)
        expected = q115_fma(rq_q, rs_q, rt_q)
        
        # Allow 1 LSB tolerance for truncation vs rounding differences
        if not q115_close(hw_result, expected, tolerance=1):
            mismatches += 1
            passed = False
            logger.log_message(f"  [{i}] MISMATCH (>1 LSB):")
            logger.log_message(f"    RS={format_q115(rs_q)}, RT={format_q115(rt_q)}, RQ={format_q115(rq_q)}")
            logger.log_message(f"    HW={format_q115(hw_result)}, Expected={format_q115(expected)}")
    
    logger.log_message(f"\nRandom tests: {num_tests - mismatches}/{num_tests} passed")
    logger.log_message(f"Overall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, f"FMA random test failed with {mismatches} mismatches"


@cocotb.test()
async def test_fma_matmul_sequence(dut):
    """
    Test FMA in a matrix multiplication sequence.
    Simulates computing one element of C = A * B using FMA chain.
    """
    logger = await setup_fma_test(dut, "fma_matmul_sequence")
    
    # A[row] = [0.5, 0.25]
    # B[col] = [0.5, 0.25]
    # C[row][col] = A[row][0]*B[0][col] + A[row][1]*B[1][col]
    #             = 0.5*0.5 + 0.25*0.25 = 0.25 + 0.0625 = 0.3125
    
    a_row = [float_to_q115(0.5), float_to_q115(0.25)]
    b_col = [float_to_q115(0.5), float_to_q115(0.25)]
    
    # Expected result using Python reference
    acc = 0
    for i in range(2):
        acc = q115_fma(acc, a_row[i], b_col[i])
    expected = acc
    
    # Execute FMA chain on hardware
    hw_acc = 0
    for i in range(2):
        logger.log_message(f"  Step {i}: acc={format_q115(hw_acc)}, a={format_q115(a_row[i])}, b={format_q115(b_col[i])}")
        hw_acc = await execute_fma(dut, a_row[i], b_col[i], hw_acc)
        logger.log_message(f"    -> acc={format_q115(hw_acc)}")
    
    passed = hw_acc == expected
    
    logger.log_message(f"\nFinal result: HW={format_q115(hw_acc)}, Expected={format_q115(expected)}")
    logger.log_message(f"Expected float: {q115_to_float(expected):.6f}")
    logger.log_message(f"Theoretical: 0.5*0.5 + 0.25*0.25 = 0.3125")
    logger.log_message(f"Overall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "FMA matmul sequence test failed"

