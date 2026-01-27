"""
Systolic PE Unit Tests for Atreides GPU

Tests the Processing Element with:
- Weight loading
- MAC (Multiply-Accumulate) operation
- Accumulator clear
- Data passthrough (systolic flow)
- Q1.15 arithmetic verification
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
import random
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from helpers.q115 import float_to_q115, q115_to_float, q115_mul, q115_add
from helpers.logger import GPULogger

PE_MAC_PIPE_LATENCY = 2  # must match systolic_pe MAC_PIPE_LATENCY


async def setup_pe_test(dut, test_name: str, clock_period_ns: int = 10) -> GPULogger:
    """Set up PE test environment."""
    logger = GPULogger(test_name, log_dir="test/results")
    logger.set_verbose(True)
    
    logger.log_section(f"Systolic PE Unit Test: {test_name}")
    
    # Start clock
    clock = Clock(dut.clk, clock_period_ns, units="ns")
    cocotb.start_soon(clock.start())
    
    # Initialize signals
    dut.reset.value = 1
    dut.enable.value = 0
    dut.clear_acc.value = 0
    dut.load_weight.value = 0
    dut.compute_enable.value = 0
    dut.a_in.value = 0
    dut.b_in.value = 0
    
    # Wait for reset
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    dut.enable.value = 1
    await ClockCycles(dut.clk, 2)
    
    return logger


async def load_weight(dut, weight: int):
    """Load a weight into the PE's stationary register."""
    dut.b_in.value = weight
    dut.load_weight.value = 1
    await RisingEdge(dut.clk)
    dut.load_weight.value = 0


async def clear_accumulator(dut):
    """Clear the PE's accumulator."""
    dut.clear_acc.value = 1
    await RisingEdge(dut.clk)
    dut.clear_acc.value = 0


async def compute_mac(dut, activation: int) -> int:
    """
    Perform one MAC operation: acc += activation * weight
    
    Args:
        dut: Device under test
        activation: Activation value (Q1.15)
        
    Returns:
        Current accumulator output (Q1.15)
    """
    dut.a_in.value = activation
    dut.compute_enable.value = 1
    await RisingEdge(dut.clk)
    dut.compute_enable.value = 0
    await ClockCycles(dut.clk, PE_MAC_PIPE_LATENCY)  # Wait for pipelined result
    
    return int(dut.acc_out.value)


def format_q115(val: int) -> str:
    """Format Q1.15 value as hex and float."""
    return f"0x{val:04X} ({q115_to_float(val):+.6f})"


def q115_mac(acc: int, a: int, w: int) -> int:
    """MAC operation in Q1.15: acc + (a * w)."""
    product = q115_mul(a, w)
    return q115_add(acc, product)


@cocotb.test()
async def test_pe_weight_load(dut):
    """Test loading weights into PE."""
    logger = await setup_pe_test(dut, "pe_weight_load")
    
    test_weights = [
        float_to_q115(0.5),
        float_to_q115(-0.25),
        float_to_q115(0.125),
        float_to_q115(0.999),
    ]
    
    passed = True
    
    for weight in test_weights:
        await load_weight(dut, weight)
        
        # Verify weight is loaded by doing a multiply and checking result
        await clear_accumulator(dut)
        
        # Multiply by 0.5 (0x4000)
        activation = float_to_q115(0.5)
        result = await compute_mac(dut, activation)
        
        expected = q115_mac(0, activation, weight)
        
        match = result == expected
        if not match:
            passed = False
        
        status = "PASS" if match else "FAIL"
        logger.log_message(f"  Weight={format_q115(weight)}")
        logger.log_message(f"    0.5 * weight = HW={format_q115(result)}, Expected={format_q115(expected)} [{status}]")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "PE weight load test failed"


@cocotb.test()
async def test_pe_basic_mac(dut):
    """Test basic MAC operation."""
    logger = await setup_pe_test(dut, "pe_basic_mac")
    
    test_cases = [
        # (weight, activation, description)
        (0.5, 0.5, "0.5 * 0.5 = 0.25"),
        (0.25, 0.5, "0.25 * 0.5 = 0.125"),
        (-0.5, 0.5, "-0.5 * 0.5 = -0.25"),
        (0.5, -0.5, "0.5 * -0.5 = -0.25"),
        (-0.5, -0.5, "-0.5 * -0.5 = 0.25"),
    ]
    
    passed = True
    
    for w_f, a_f, desc in test_cases:
        w_q = float_to_q115(w_f)
        a_q = float_to_q115(a_f)
        
        await load_weight(dut, w_q)
        await clear_accumulator(dut)
        
        result = await compute_mac(dut, a_q)
        expected = q115_mac(0, a_q, w_q)
        
        match = result == expected
        if not match:
            passed = False
        
        status = "PASS" if match else "FAIL"
        logger.log_message(f"  {desc}")
        logger.log_message(f"    Weight={format_q115(w_q)}, Act={format_q115(a_q)}")
        logger.log_message(f"    HW={format_q115(result)}, Expected={format_q115(expected)} [{status}]")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "PE basic MAC test failed"


@cocotb.test()
async def test_pe_accumulation(dut):
    """Test accumulation over multiple MAC operations."""
    logger = await setup_pe_test(dut, "pe_accumulation")
    
    # Load weight
    weight = float_to_q115(0.5)
    await load_weight(dut, weight)
    await clear_accumulator(dut)
    
    # Stream of activations
    activations = [
        float_to_q115(0.1),
        float_to_q115(0.2),
        float_to_q115(0.3),
        float_to_q115(0.1),
    ]
    
    logger.log_message(f"  Weight = {format_q115(weight)}")
    logger.log_message(f"  Accumulating: act[i] * weight for i in 0..{len(activations)-1}")
    
    # Track expected accumulator
    expected_acc = 0
    passed = True
    
    for i, act in enumerate(activations):
        result = await compute_mac(dut, act)
        expected_acc = q115_mac(expected_acc, act, weight)
        
        match = result == expected_acc
        if not match:
            passed = False
        
        status = "PASS" if match else "FAIL"
        logger.log_message(f"    Step {i}: act={format_q115(act)}")
        logger.log_message(f"      HW acc={format_q115(result)}, Expected={format_q115(expected_acc)} [{status}]")
    
    logger.log_message(f"\n  Final accumulated value: {format_q115(result)}")
    logger.log_message(f"  Expected: 0.1*0.5 + 0.2*0.5 + 0.3*0.5 + 0.1*0.5 = 0.35")
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "PE accumulation test failed"


@cocotb.test()
async def test_pe_clear_accumulator(dut):
    """Test accumulator clear functionality."""
    logger = await setup_pe_test(dut, "pe_clear_acc")
    
    # Load weight and accumulate some values
    weight = float_to_q115(0.5)
    await load_weight(dut, weight)
    
    act = float_to_q115(0.5)
    await compute_mac(dut, act)
    await compute_mac(dut, act)
    
    result_before = int(dut.acc_out.value)
    logger.log_message(f"  Acc before clear: {format_q115(result_before)}")
    
    # Clear accumulator
    await clear_accumulator(dut)
    await RisingEdge(dut.clk)
    
    result_after = int(dut.acc_out.value)
    logger.log_message(f"  Acc after clear: {format_q115(result_after)}")
    
    passed = result_after == 0
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "PE clear accumulator test failed"


@cocotb.test()
async def test_pe_data_passthrough(dut):
    """Test systolic data passthrough (a_out, b_out)."""
    logger = await setup_pe_test(dut, "pe_passthrough")
    
    test_values = [
        (float_to_q115(0.5), float_to_q115(0.25)),
        (float_to_q115(-0.5), float_to_q115(0.75)),
        (float_to_q115(0.125), float_to_q115(-0.5)),
    ]
    
    passed = True
    
    for a_in, b_in in test_values:
        dut.a_in.value = a_in
        dut.b_in.value = b_in
        await RisingEdge(dut.clk)
        await RisingEdge(dut.clk)  # Passthrough has 1 cycle delay
        
        a_out = int(dut.a_out.value)
        b_out = int(dut.b_out.value)
        
        a_match = a_out == a_in
        b_match = b_out == b_in
        
        if not a_match or not b_match:
            passed = False
        
        status = "PASS" if (a_match and b_match) else "FAIL"
        logger.log_message(f"  a_in={format_q115(a_in)} -> a_out={format_q115(a_out)} [{status}]")
        logger.log_message(f"  b_in={format_q115(b_in)} -> b_out={format_q115(b_out)} [{status}]")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "PE data passthrough test failed"


@cocotb.test()
async def test_pe_dot_product(dut):
    """
    Test PE computing a dot product (simulates one row of matrix multiply).
    Computes: sum(a[i] * w) for a sequence of activations.
    """
    logger = await setup_pe_test(dut, "pe_dot_product")
    
    # Simulate row of matrix A and weight (column of B)
    # A_row = [0.1, 0.2, 0.3, 0.4]
    # W = 0.5
    # Expected: 0.1*0.5 + 0.2*0.5 + 0.3*0.5 + 0.4*0.5 = 0.5
    
    a_row = [float_to_q115(0.1), float_to_q115(0.2), 
             float_to_q115(0.3), float_to_q115(0.4)]
    weight = float_to_q115(0.5)
    
    await load_weight(dut, weight)
    await clear_accumulator(dut)
    
    logger.log_message(f"  Computing dot product: A_row * W")
    logger.log_message(f"  A_row = [0.1, 0.2, 0.3, 0.4]")
    logger.log_message(f"  W = 0.5")
    logger.log_message(f"  Expected: 0.1*0.5 + 0.2*0.5 + 0.3*0.5 + 0.4*0.5 = 0.5")
    
    expected_acc = 0
    for act in a_row:
        await compute_mac(dut, act)
        expected_acc = q115_mac(expected_acc, act, weight)
    
    result = int(dut.acc_out.value)
    
    match = result == expected_acc
    
    logger.log_message(f"\n  HW Result: {format_q115(result)}")
    logger.log_message(f"  Expected:  {format_q115(expected_acc)}")
    logger.log_message(f"  Float expected: {q115_to_float(expected_acc):.6f}")
    logger.log_message(f"\nOverall: {'PASS' if match else 'FAIL'}")
    logger.close()
    
    assert match, "PE dot product test failed"


@cocotb.test()
async def test_pe_saturation(dut):
    """Test PE accumulator saturation."""
    logger = await setup_pe_test(dut, "pe_saturation")
    
    Q115_MAX = 0x7FFF
    Q115_MIN = 0x8000
    
    # Try to overflow positive
    weight = float_to_q115(0.999)
    await load_weight(dut, weight)
    await clear_accumulator(dut)
    
    logger.log_message(f"  Testing positive overflow with repeated 0.999 * 0.999")
    
    for i in range(10):
        act = float_to_q115(0.999)
        await compute_mac(dut, act)
        result = int(dut.acc_out.value)
        logger.log_message(f"    Step {i}: acc={format_q115(result)}")
    
    final_result = int(dut.acc_out.value)
    
    # Should be saturated at max
    passed = final_result == Q115_MAX
    
    logger.log_message(f"\n  Final result: {format_q115(final_result)}")
    logger.log_message(f"  Q115_MAX: {format_q115(Q115_MAX)}")
    logger.log_message(f"  Saturated: {final_result == Q115_MAX}")
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "PE saturation test failed"


def q115_close(a: int, b: int, tolerance: int = 1) -> bool:
    """Check if two Q1.15 values are within tolerance (LSBs)."""
    a_signed = a if a < 32768 else a - 65536
    b_signed = b if b < 32768 else b - 65536
    return abs(a_signed - b_signed) <= tolerance


@cocotb.test()
async def test_pe_random(dut):
    """Test PE with random values."""
    logger = await setup_pe_test(dut, "pe_random")
    
    random.seed(42)
    num_sequences = 10
    
    passed = True
    
    logger.log_message(f"Running {num_sequences} random MAC sequences...")
    logger.log_message("(Allowing 1 LSB tolerance for truncation vs rounding)")
    
    for seq in range(num_sequences):
        # Random weight
        w_f = random.uniform(-0.9, 0.9)
        w_q = float_to_q115(w_f)
        await load_weight(dut, w_q)
        await clear_accumulator(dut)
        
        # Random number of activations
        num_macs = random.randint(2, 8)
        expected_acc = 0
        
        for _ in range(num_macs):
            a_f = random.uniform(-0.5, 0.5)
            a_q = float_to_q115(a_f)
            await compute_mac(dut, a_q)
            expected_acc = q115_mac(expected_acc, a_q, w_q)
        
        result = int(dut.acc_out.value)
        
        # Allow 1 LSB tolerance per MAC operation (accumulates)
        if not q115_close(result, expected_acc, tolerance=num_macs):
            passed = False
            logger.log_message(f"  Seq {seq}: MISMATCH - HW={format_q115(result)}, Expected={format_q115(expected_acc)}")
        else:
            logger.log_message(f"  Seq {seq}: {num_macs} MACs, result={format_q115(result)} [PASS]")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "PE random test failed"
