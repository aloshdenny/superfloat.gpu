"""
ALU Unit Tests for Atreides GPU

Tests the integer Arithmetic Logic Unit with comprehensive test cases:
- ADD: Integer addition
- SUB: Integer subtraction
- MUL: Integer multiplication
- DIV: Integer division
- CMP: Compare (sets NZP flags)
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
import random
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from helpers.logger import GPULogger


# Core states from the design
STATE_IDLE = 0b000
STATE_FETCH = 0b001
STATE_DECODE = 0b010
STATE_REQUEST = 0b011
STATE_WAIT = 0b100
STATE_EXECUTE = 0b101
STATE_UPDATE = 0b110

# ALU operations
ALU_ADD = 0b00
ALU_SUB = 0b01
ALU_MUL = 0b10
ALU_DIV = 0b11


async def setup_alu_test(dut, test_name: str, clock_period_ns: int = 10) -> GPULogger:
    """Set up ALU unit test environment."""
    logger = GPULogger(test_name, log_dir="test/results")
    logger.set_verbose(True)
    
    logger.log_section(f"ALU Unit Test: {test_name}")
    
    # Start clock
    clock = Clock(dut.clk, clock_period_ns, units="ns")
    cocotb.start_soon(clock.start())
    
    # Initialize signals
    dut.reset.value = 1
    dut.enable.value = 0
    dut.core_state.value = STATE_IDLE
    dut.alu_arithmetic_mux.value = ALU_ADD
    dut.alu_output_mux.value = 0
    dut.rs.value = 0
    dut.rt.value = 0
    
    # Wait for reset
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    dut.enable.value = 1
    await ClockCycles(dut.clk, 2)
    
    return logger


async def execute_alu_op(dut, rs: int, rt: int, op: int, is_compare: bool = False) -> int:
    """
    Execute a single ALU operation.
    
    Args:
        dut: Device under test
        rs: First operand (16-bit)
        rt: Second operand (16-bit)
        op: ALU operation (ADD=0, SUB=1, MUL=2, DIV=3)
        is_compare: If True, use CMP mode (sets NZP flags)
        
    Returns:
        ALU result (16-bit)
    """
    # Set inputs
    dut.rs.value = rs & 0xFFFF
    dut.rt.value = rt & 0xFFFF
    dut.alu_arithmetic_mux.value = op
    dut.alu_output_mux.value = 1 if is_compare else 0
    
    # Execute in EXECUTE state
    dut.core_state.value = STATE_EXECUTE
    await RisingEdge(dut.clk)
    
    # Wait for result
    await RisingEdge(dut.clk)
    
    # Read result
    dut.core_state.value = STATE_IDLE
    result = int(dut.alu_out.value)
    return result


def to_signed(val: int, bits: int = 16) -> int:
    """Convert unsigned to signed representation."""
    if val >= (1 << (bits - 1)):
        return val - (1 << bits)
    return val


def to_unsigned(val: int, bits: int = 16) -> int:
    """Convert signed to unsigned representation."""
    if val < 0:
        return val + (1 << bits)
    return val & ((1 << bits) - 1)


@cocotb.test()
async def test_alu_add(dut):
    """Test ALU integer addition."""
    logger = await setup_alu_test(dut, "alu_add")
    
    test_cases = [
        # (rs, rt, description)
        (5, 3, "5 + 3 = 8"),
        (100, 200, "100 + 200 = 300"),
        (0, 0, "0 + 0 = 0"),
        (0xFFFF, 1, "65535 + 1 = 0 (overflow wrap)"),
        (0x7FFF, 0x7FFF, "32767 + 32767 = 65534"),
        (1000, 2000, "1000 + 2000 = 3000"),
    ]
    
    passed = True
    
    for rs, rt, desc in test_cases:
        hw_result = await execute_alu_op(dut, rs, rt, ALU_ADD)
        expected = (rs + rt) & 0xFFFF
        
        match = hw_result == expected
        if not match:
            passed = False
        
        status = "PASS" if match else "FAIL"
        logger.log_message(f"  {desc}")
        logger.log_message(f"    RS=0x{rs:04X}, RT=0x{rt:04X}")
        logger.log_message(f"    HW=0x{hw_result:04X} ({hw_result}), Expected=0x{expected:04X} ({expected}) [{status}]")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "ALU ADD test failed"


@cocotb.test()
async def test_alu_sub(dut):
    """Test ALU integer subtraction."""
    logger = await setup_alu_test(dut, "alu_sub")
    
    test_cases = [
        # (rs, rt, description)
        (10, 3, "10 - 3 = 7"),
        (100, 100, "100 - 100 = 0"),
        (0, 1, "0 - 1 = 65535 (underflow wrap)"),
        (500, 200, "500 - 200 = 300"),
        (0xFFFF, 0xFFFF, "65535 - 65535 = 0"),
    ]
    
    passed = True
    
    for rs, rt, desc in test_cases:
        hw_result = await execute_alu_op(dut, rs, rt, ALU_SUB)
        expected = (rs - rt) & 0xFFFF
        
        match = hw_result == expected
        if not match:
            passed = False
        
        status = "PASS" if match else "FAIL"
        logger.log_message(f"  {desc}")
        logger.log_message(f"    RS=0x{rs:04X}, RT=0x{rt:04X}")
        logger.log_message(f"    HW=0x{hw_result:04X} ({hw_result}), Expected=0x{expected:04X} ({expected}) [{status}]")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "ALU SUB test failed"


@cocotb.test()
async def test_alu_mul(dut):
    """Test ALU integer multiplication."""
    logger = await setup_alu_test(dut, "alu_mul")
    
    test_cases = [
        # (rs, rt, description)
        (5, 3, "5 * 3 = 15"),
        (10, 10, "10 * 10 = 100"),
        (0, 1000, "0 * 1000 = 0"),
        (256, 256, "256 * 256 = 65536 -> 0 (overflow)"),
        (100, 100, "100 * 100 = 10000"),
        (2, 3, "2 * 3 = 6"),
    ]
    
    passed = True
    
    for rs, rt, desc in test_cases:
        hw_result = await execute_alu_op(dut, rs, rt, ALU_MUL)
        expected = (rs * rt) & 0xFFFF
        
        match = hw_result == expected
        if not match:
            passed = False
        
        status = "PASS" if match else "FAIL"
        logger.log_message(f"  {desc}")
        logger.log_message(f"    RS={rs}, RT={rt}")
        logger.log_message(f"    HW=0x{hw_result:04X} ({hw_result}), Expected=0x{expected:04X} ({expected}) [{status}]")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "ALU MUL test failed"


@cocotb.test()
async def test_alu_div(dut):
    """Test ALU integer division."""
    logger = await setup_alu_test(dut, "alu_div")
    
    test_cases = [
        # (rs, rt, description)
        (10, 2, "10 / 2 = 5"),
        (100, 10, "100 / 10 = 10"),
        (7, 3, "7 / 3 = 2 (integer division)"),
        (1000, 7, "1000 / 7 = 142"),
        (5, 10, "5 / 10 = 0 (smaller / larger)"),
        (0, 5, "0 / 5 = 0"),
        (100, 0, "100 / 0 = 0 (div by zero protection)"),
    ]
    
    passed = True
    
    for rs, rt, desc in test_cases:
        hw_result = await execute_alu_op(dut, rs, rt, ALU_DIV)
        
        # Expected: division by zero returns 0
        if rt == 0:
            expected = 0
        else:
            expected = rs // rt
        
        match = hw_result == expected
        if not match:
            passed = False
        
        status = "PASS" if match else "FAIL"
        logger.log_message(f"  {desc}")
        logger.log_message(f"    RS={rs}, RT={rt}")
        logger.log_message(f"    HW={hw_result}, Expected={expected} [{status}]")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "ALU DIV test failed"


@cocotb.test()
async def test_alu_cmp(dut):
    """Test ALU compare operation (sets NZP flags)."""
    logger = await setup_alu_test(dut, "alu_cmp")
    
    # ALU outputs: bit 2 = (rs < rt), bit 1 = (rs == rt), bit 0 = (rs > rt)
    # This matches LC-3 style BR masks (N,Z,P).
    test_cases = [
        # (rs, rt, expected_nzp, description)
        (10, 5, 0b001, "10 > 5 -> positive (bit 0)"),
        (5, 10, 0b100, "5 < 10 -> negative (bit 2)"),
        (5, 5, 0b010, "5 == 5 -> zero (bit 1)"),
        (0, 0, 0b010, "0 == 0 -> zero"),
        (0xFFFF, 0, 0b100, "-1 < 0 -> negative (signed)"),
        (0, 0xFFFF, 0b001, "0 > -1 -> positive (signed)"),
        (0x7FFF, 0x8000, 0b001, "32767 > -32768 -> positive (signed)"),
    ]
    
    passed = True
    
    for rs, rt, expected_nzp, desc in test_cases:
        hw_result = await execute_alu_op(dut, rs, rt, ALU_ADD, is_compare=True)
        
        # Extract NZP bits from result (bit2=N, bit1=Z, bit0=P)
        hw_nzp = hw_result & 0b111
        
        match = hw_nzp == expected_nzp
        if not match:
            passed = False
        
        status = "PASS" if match else "FAIL"
        nzp_str = lambda x: f"N={x>>2&1} Z={x>>1&1} P={x&1}"
        logger.log_message(f"  {desc}")
        logger.log_message(f"    RS=0x{rs:04X} ({to_signed(rs)}), RT=0x{rt:04X} ({to_signed(rt)})")
        logger.log_message(f"    HW NZP={nzp_str(hw_nzp)}, Expected NZP={nzp_str(expected_nzp)} [{status}]")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "ALU CMP test failed"


@cocotb.test()
async def test_alu_indexing_sequence(dut):
    """
    Test ALU operations for matrix indexing.
    Simulates calculating row and col from linear index:
    row = i / N, col = i % N (where N is matrix dimension)
    """
    logger = await setup_alu_test(dut, "alu_indexing")
    
    N = 4  # 4x4 matrix
    
    logger.log_message(f"Testing matrix indexing for {N}x{N} matrix")
    logger.log_message("For linear index i: row = i / N, col = i - row * N")
    
    passed = True
    
    for i in range(N * N):
        expected_row = i // N
        expected_col = i % N
        
        # row = i / N
        hw_row = await execute_alu_op(dut, i, N, ALU_DIV)
        
        # temp = row * N
        hw_temp = await execute_alu_op(dut, hw_row, N, ALU_MUL)
        
        # col = i - temp (i.e., i % N)
        hw_col = await execute_alu_op(dut, i, hw_temp, ALU_SUB)
        
        row_match = hw_row == expected_row
        col_match = hw_col == expected_col
        
        if not row_match or not col_match:
            passed = False
            logger.log_message(f"  i={i}: row={hw_row} (exp={expected_row}), col={hw_col} (exp={expected_col}) [FAIL]")
        else:
            logger.log_message(f"  i={i}: row={hw_row}, col={hw_col} [PASS]")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "ALU indexing sequence test failed"


@cocotb.test()
async def test_alu_random(dut):
    """Test ALU with random values."""
    logger = await setup_alu_test(dut, "alu_random")
    
    random.seed(42)
    num_tests = 25
    
    passed = True
    
    logger.log_message(f"Running {num_tests} random tests per operation...")
    
    for op_name, op_code, op_func in [
        ("ADD", ALU_ADD, lambda a, b: (a + b) & 0xFFFF),
        ("SUB", ALU_SUB, lambda a, b: (a - b) & 0xFFFF),
        ("MUL", ALU_MUL, lambda a, b: (a * b) & 0xFFFF),
        ("DIV", ALU_DIV, lambda a, b: (a // b) if b != 0 else 0),
    ]:
        mismatches = 0
        for _ in range(num_tests):
            rs = random.randint(0, 0xFFFF)
            rt = random.randint(0, 0xFFFF)
            
            # Avoid div by zero in test generation
            if op_code == ALU_DIV and rt == 0:
                rt = 1
            
            hw_result = await execute_alu_op(dut, rs, rt, op_code)
            expected = op_func(rs, rt)
            
            if hw_result != expected:
                mismatches += 1
                passed = False
        
        logger.log_message(f"  {op_name}: {num_tests - mismatches}/{num_tests} passed")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "ALU random test failed"
