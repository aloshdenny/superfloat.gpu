"""
Activation Unit Tests for Atreides GPU

Tests the Activation unit with all supported functions:
- Pass-through (no activation)
- ReLU: max(0, x)
- Leaky ReLU: x if x > 0, else ~0.01*x
- Clipped ReLU: min(max_val, max(0, x))

Also tests bias addition with saturation.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
import random
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from helpers.q115 import float_to_q115, q115_to_float, q115_add
from helpers.logger import GPULogger


# Core states from the design
STATE_IDLE = 0b000
STATE_FETCH = 0b001
STATE_DECODE = 0b010
STATE_REQUEST = 0b011
STATE_WAIT = 0b100
STATE_EXECUTE = 0b101
STATE_UPDATE = 0b110

# Activation function codes
ACT_NONE = 0b00
ACT_RELU = 0b01
ACT_LEAKY_RELU = 0b10
ACT_CLIPPED_RELU = 0b11


def q115_relu(x: int) -> int:
    """ReLU activation: max(0, x) in Q1.15."""
    # Check sign bit
    if x & 0x8000:  # Negative
        return 0
    return x


def q115_leaky_relu(x: int) -> int:
    """Leaky ReLU: x if x > 0, else ~0.01*x (approx x >> 7) in Q1.15."""
    if x & 0x8000:  # Negative
        # Convert to signed, shift right 7 (divide by ~128), convert back
        x_signed = x - 0x10000 if x & 0x8000 else x
        result = x_signed >> 7
        if result < 0:
            result = result + 0x10000
        return result & 0xFFFF
    return x


def q115_clipped_relu(x: int) -> int:
    """Clipped ReLU: min(max_val, max(0, x)) in Q1.15."""
    if x & 0x8000:  # Negative
        return 0
    return x  # Q1.15 max is already ~1.0


def q115_activation(x: int, bias: int, func: int) -> int:
    """Apply bias and activation function in Q1.15."""
    # First add bias
    biased = q115_add(x, bias)
    
    # Then apply activation
    if func == ACT_NONE:
        return biased
    elif func == ACT_RELU:
        return q115_relu(biased)
    elif func == ACT_LEAKY_RELU:
        return q115_leaky_relu(biased)
    elif func == ACT_CLIPPED_RELU:
        return q115_clipped_relu(biased)
    return biased


async def setup_activation_test(dut, test_name: str, clock_period_ns: int = 10) -> GPULogger:
    """Set up Activation unit test environment."""
    logger = GPULogger(test_name, log_dir="test/results")
    logger.set_verbose(True)
    
    logger.log_section(f"Activation Unit Test: {test_name}")
    
    # Start clock
    clock = Clock(dut.clk, clock_period_ns, units="ns")
    cocotb.start_soon(clock.start())
    
    # Initialize signals
    dut.reset.value = 1
    dut.enable.value = 0
    dut.core_state.value = STATE_IDLE
    dut.activation_enable.value = 0
    dut.activation_func.value = ACT_NONE
    dut.unbiased_activation.value = 0
    dut.bias.value = 0
    
    # Wait for reset
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    dut.enable.value = 1
    await ClockCycles(dut.clk, 2)
    
    return logger


async def execute_activation(dut, x: int, bias: int, func: int) -> int:
    """
    Execute activation unit: result = act_func(x + bias)
    
    Args:
        dut: Device under test
        x: Input value (Q1.15)
        bias: Bias value (Q1.15)
        func: Activation function code
        
    Returns:
        Activation result (Q1.15)
    """
    # Load bias in REQUEST state
    dut.core_state.value = STATE_REQUEST
    dut.bias.value = bias
    await RisingEdge(dut.clk)
    
    # Execute in EXECUTE state
    dut.core_state.value = STATE_EXECUTE
    dut.unbiased_activation.value = x
    dut.activation_func.value = func
    dut.activation_enable.value = 1
    await RisingEdge(dut.clk)
    
    # Wait for pipeline
    await RisingEdge(dut.clk)
    
    # Read result
    dut.activation_enable.value = 0
    dut.core_state.value = STATE_IDLE
    
    result = int(dut.activation_out.value)
    return result


def format_q115(val: int) -> str:
    """Format Q1.15 value as hex and float."""
    return f"0x{val:04X} ({q115_to_float(val):+.6f})"


def act_name(func: int) -> str:
    """Get activation function name."""
    names = {ACT_NONE: "NONE", ACT_RELU: "ReLU", ACT_LEAKY_RELU: "LeakyReLU", ACT_CLIPPED_RELU: "ClippedReLU"}
    return names.get(func, "UNKNOWN")


@cocotb.test()
async def test_activation_passthrough(dut):
    """Test pass-through (no activation)."""
    logger = await setup_activation_test(dut, "activation_passthrough")
    
    test_cases = [
        # (input, bias, description)
        (0.5, 0.0, "positive, no bias"),
        (-0.5, 0.0, "negative, no bias"),
        (0.0, 0.0, "zero, no bias"),
        (0.25, 0.125, "positive + positive bias"),
        (0.25, -0.125, "positive + negative bias"),
        (-0.25, 0.5, "negative + positive bias"),
    ]
    
    passed = True
    
    for x_f, bias_f, desc in test_cases:
        x_q = float_to_q115(x_f)
        bias_q = float_to_q115(bias_f)
        
        hw_result = await execute_activation(dut, x_q, bias_q, ACT_NONE)
        expected = q115_activation(x_q, bias_q, ACT_NONE)
        
        match = hw_result == expected
        if not match:
            passed = False
        
        status = "PASS" if match else "FAIL"
        logger.log_message(f"  {desc}")
        logger.log_message(f"    Input={format_q115(x_q)}, Bias={format_q115(bias_q)}")
        logger.log_message(f"    HW={format_q115(hw_result)}, Expected={format_q115(expected)} [{status}]")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Activation pass-through test failed"


@cocotb.test()
async def test_activation_relu(dut):
    """Test ReLU activation: max(0, x)."""
    logger = await setup_activation_test(dut, "activation_relu")
    
    test_cases = [
        # (input, bias, description)
        (0.5, 0.0, "positive -> stays positive"),
        (-0.5, 0.0, "negative -> zero"),
        (0.0, 0.0, "zero -> zero"),
        (0.1, 0.0, "small positive -> stays"),
        (-0.1, 0.0, "small negative -> zero"),
        (-0.25, 0.5, "neg + bias = positive -> stays"),
        (0.25, -0.5, "pos + neg bias = negative -> zero"),
    ]
    
    passed = True
    
    for x_f, bias_f, desc in test_cases:
        x_q = float_to_q115(x_f)
        bias_q = float_to_q115(bias_f)
        
        hw_result = await execute_activation(dut, x_q, bias_q, ACT_RELU)
        expected = q115_activation(x_q, bias_q, ACT_RELU)
        
        match = hw_result == expected
        if not match:
            passed = False
        
        status = "PASS" if match else "FAIL"
        logger.log_message(f"  {desc}")
        logger.log_message(f"    Input={format_q115(x_q)}, Bias={format_q115(bias_q)}")
        logger.log_message(f"    HW={format_q115(hw_result)}, Expected={format_q115(expected)} [{status}]")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Activation ReLU test failed"


@cocotb.test()
async def test_activation_leaky_relu(dut):
    """Test Leaky ReLU: x if x > 0, else ~0.01*x."""
    logger = await setup_activation_test(dut, "activation_leaky_relu")
    
    test_cases = [
        # (input, bias, description)
        (0.5, 0.0, "positive -> unchanged"),
        (-0.5, 0.0, "negative -> ~-0.004 (x/128)"),
        (0.0, 0.0, "zero -> zero"),
        (0.25, 0.0, "positive -> unchanged"),
        (-0.25, 0.0, "negative -> ~-0.002"),
        (-1.0, 0.0, "max negative -> ~-0.008"),
    ]
    
    passed = True
    
    for x_f, bias_f, desc in test_cases:
        x_q = float_to_q115(x_f)
        bias_q = float_to_q115(bias_f)
        
        hw_result = await execute_activation(dut, x_q, bias_q, ACT_LEAKY_RELU)
        expected = q115_activation(x_q, bias_q, ACT_LEAKY_RELU)
        
        # Allow small tolerance for leaky ReLU due to approximation
        hw_float = q115_to_float(hw_result)
        exp_float = q115_to_float(expected)
        tolerance = 0.01  # 1% tolerance for approximation
        
        match = abs(hw_float - exp_float) <= tolerance or hw_result == expected
        if not match:
            passed = False
        
        status = "PASS" if match else "FAIL"
        logger.log_message(f"  {desc}")
        logger.log_message(f"    Input={format_q115(x_q)}, Bias={format_q115(bias_q)}")
        logger.log_message(f"    HW={format_q115(hw_result)}, Expected={format_q115(expected)} [{status}]")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Activation Leaky ReLU test failed"


@cocotb.test()
async def test_activation_clipped_relu(dut):
    """Test Clipped ReLU: min(max_val, max(0, x))."""
    logger = await setup_activation_test(dut, "activation_clipped_relu")
    
    test_cases = [
        # (input, bias, description)
        (0.5, 0.0, "positive -> unchanged"),
        (-0.5, 0.0, "negative -> zero"),
        (0.0, 0.0, "zero -> zero"),
        (0.999, 0.0, "near max -> near max"),
        (-0.999, 0.0, "near min -> zero"),
    ]
    
    passed = True
    
    for x_f, bias_f, desc in test_cases:
        x_q = float_to_q115(x_f)
        bias_q = float_to_q115(bias_f)
        
        hw_result = await execute_activation(dut, x_q, bias_q, ACT_CLIPPED_RELU)
        expected = q115_activation(x_q, bias_q, ACT_CLIPPED_RELU)
        
        match = hw_result == expected
        if not match:
            passed = False
        
        status = "PASS" if match else "FAIL"
        logger.log_message(f"  {desc}")
        logger.log_message(f"    Input={format_q115(x_q)}, Bias={format_q115(bias_q)}")
        logger.log_message(f"    HW={format_q115(hw_result)}, Expected={format_q115(expected)} [{status}]")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Activation Clipped ReLU test failed"


@cocotb.test()
async def test_activation_bias_saturation(dut):
    """Test bias addition with saturation."""
    logger = await setup_activation_test(dut, "activation_bias_saturation")
    
    Q115_MAX = 0x7FFF
    Q115_MIN = 0x8000
    
    test_cases = [
        # (input, bias, description)
        (Q115_MAX, 0x1000, "near max + positive -> saturate"),
        (Q115_MIN, 0xF000, "near min + negative -> saturate"),
        (0x4000, 0x4000, "half + half -> no saturation"),
    ]
    
    passed = True
    
    for x_q, bias_q, desc in test_cases:
        hw_result = await execute_activation(dut, x_q, bias_q, ACT_NONE)
        expected = q115_activation(x_q, bias_q, ACT_NONE)
        
        match = hw_result == expected
        if not match:
            passed = False
        
        status = "PASS" if match else "FAIL"
        logger.log_message(f"  {desc}")
        logger.log_message(f"    Input={format_q115(x_q)}, Bias={format_q115(bias_q)}")
        logger.log_message(f"    HW={format_q115(hw_result)}, Expected={format_q115(expected)} [{status}]")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Activation bias saturation test failed"


@cocotb.test()
async def test_activation_all_functions(dut):
    """Test all activation functions with same inputs for comparison."""
    logger = await setup_activation_test(dut, "activation_all_functions")
    
    test_inputs = [
        (0.5, 0.0, "positive"),
        (-0.5, 0.0, "negative"),
        (0.0, 0.125, "zero with bias"),
        (-0.25, 0.25, "negative with positive bias"),
    ]
    
    passed = True
    
    for x_f, bias_f, desc in test_inputs:
        x_q = float_to_q115(x_f)
        bias_q = float_to_q115(bias_f)
        
        logger.log_message(f"\n  Input: x={format_q115(x_q)}, bias={format_q115(bias_q)} ({desc})")
        
        for func in [ACT_NONE, ACT_RELU, ACT_LEAKY_RELU, ACT_CLIPPED_RELU]:
            hw_result = await execute_activation(dut, x_q, bias_q, func)
            expected = q115_activation(x_q, bias_q, func)
            
            # Tolerance for leaky relu
            hw_float = q115_to_float(hw_result)
            exp_float = q115_to_float(expected)
            if func == ACT_LEAKY_RELU:
                match = abs(hw_float - exp_float) <= 0.01 or hw_result == expected
            else:
                match = hw_result == expected
            
            if not match:
                passed = False
            
            status = "PASS" if match else "FAIL"
            logger.log_message(f"    {act_name(func):12}: HW={format_q115(hw_result)} [{status}]")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Activation all functions test failed"


@cocotb.test()
async def test_activation_random(dut):
    """Test activation with random values."""
    logger = await setup_activation_test(dut, "activation_random")
    
    random.seed(42)
    num_tests = 20
    
    passed = True
    
    logger.log_message(f"Running {num_tests} random tests per activation function...")
    
    for func in [ACT_NONE, ACT_RELU, ACT_LEAKY_RELU, ACT_CLIPPED_RELU]:
        mismatches = 0
        for _ in range(num_tests):
            x_f = random.uniform(-1.0, 0.999)
            bias_f = random.uniform(-0.5, 0.5)
            
            x_q = float_to_q115(x_f)
            bias_q = float_to_q115(bias_f)
            
            hw_result = await execute_activation(dut, x_q, bias_q, func)
            expected = q115_activation(x_q, bias_q, func)
            
            # Tolerance for leaky relu
            hw_float = q115_to_float(hw_result)
            exp_float = q115_to_float(expected)
            if func == ACT_LEAKY_RELU:
                match = abs(hw_float - exp_float) <= 0.01 or hw_result == expected
            else:
                match = hw_result == expected
            
            if not match:
                mismatches += 1
                passed = False
        
        logger.log_message(f"  {act_name(func):12}: {num_tests - mismatches}/{num_tests} passed")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Activation random test failed"

