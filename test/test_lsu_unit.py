"""
LSU Unit Tests for Atreides GPU

Tests the Load-Store Unit with:
- LDR: Load from memory
- STR: Store to memory
- State machine transitions
- Memory interface timing
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


# Core states
STATE_IDLE = 0b000
STATE_FETCH = 0b001
STATE_DECODE = 0b010
STATE_REQUEST = 0b011
STATE_WAIT = 0b100
STATE_EXECUTE = 0b101
STATE_UPDATE = 0b110

# LSU states
LSU_IDLE = 0b00
LSU_REQUESTING = 0b01
LSU_WAITING = 0b10
LSU_DONE = 0b11


def expected_data(addr: int) -> int:
    """Get expected data from memory init pattern."""
    return (addr * 3 + 7) & 0xFFFF


async def setup_lsu_test(dut, test_name: str, clock_period_ns: int = 10) -> GPULogger:
    """Set up LSU test environment."""
    logger = GPULogger(test_name, log_dir="test/results")
    logger.set_verbose(True)
    
    logger.log_section(f"LSU Unit Test: {test_name}")
    
    # Start clock
    clock = Clock(dut.clk, clock_period_ns, units="ns")
    cocotb.start_soon(clock.start())
    
    # Initialize signals
    dut.reset.value = 1
    dut.enable.value = 0
    dut.core_state.value = STATE_IDLE
    dut.mem_read_enable.value = 0
    dut.mem_write_enable.value = 0
    dut.rs.value = 0
    dut.rt.value = 0
    
    # Wait for reset
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    dut.enable.value = 1
    await ClockCycles(dut.clk, 2)
    
    return logger


async def execute_load(dut, address: int, max_cycles: int = 20) -> tuple:
    """
    Execute a load operation.
    
    Args:
        dut: Device under test
        address: Memory address to load from
        max_cycles: Maximum cycles to wait
        
    Returns:
        (data, cycles) - loaded data and cycle count
    """
    # Set up load
    dut.rs.value = address
    dut.mem_read_enable.value = 1
    dut.mem_write_enable.value = 0
    
    # Start in REQUEST state
    dut.core_state.value = STATE_REQUEST
    await RisingEdge(dut.clk)
    
    # Wait for LSU to complete
    cycles = 0
    while cycles < max_cycles:
        await RisingEdge(dut.clk)
        cycles += 1
        
        lsu_state = int(dut.lsu_state.value)
        if lsu_state == LSU_DONE:
            data = int(dut.lsu_out.value)
            
            # Transition to UPDATE to reset LSU
            dut.core_state.value = STATE_UPDATE
            await RisingEdge(dut.clk)
            
            # Reset
            dut.core_state.value = STATE_IDLE
            dut.mem_read_enable.value = 0
            await RisingEdge(dut.clk)
            
            return data, cycles
    
    dut.mem_read_enable.value = 0
    dut.core_state.value = STATE_IDLE
    return None, cycles


async def execute_store(dut, address: int, data: int, max_cycles: int = 20) -> tuple:
    """
    Execute a store operation.
    
    Args:
        dut: Device under test
        address: Memory address to store to
        data: Data to store
        max_cycles: Maximum cycles to wait
        
    Returns:
        (success, cycles) - whether store completed and cycle count
    """
    # Set up store
    dut.rs.value = address
    dut.rt.value = data
    dut.mem_read_enable.value = 0
    dut.mem_write_enable.value = 1
    
    # Start in REQUEST state
    dut.core_state.value = STATE_REQUEST
    await RisingEdge(dut.clk)
    
    # Wait for LSU to complete
    cycles = 0
    while cycles < max_cycles:
        await RisingEdge(dut.clk)
        cycles += 1
        
        lsu_state = int(dut.lsu_state.value)
        if lsu_state == LSU_DONE:
            # Transition to UPDATE to reset LSU
            dut.core_state.value = STATE_UPDATE
            await RisingEdge(dut.clk)
            
            # Reset
            dut.core_state.value = STATE_IDLE
            dut.mem_write_enable.value = 0
            await RisingEdge(dut.clk)
            
            return True, cycles
    
    dut.mem_write_enable.value = 0
    dut.core_state.value = STATE_IDLE
    return False, cycles


def format_q115(val: int) -> str:
    """Format Q1.15 value."""
    return f"0x{val:04X} ({q115_to_float(val):+.6f})"


@cocotb.test()
async def test_lsu_load_basic(dut):
    """Test basic load operation."""
    logger = await setup_lsu_test(dut, "lsu_load_basic")
    
    test_addresses = [0, 10, 50, 100, 255]
    passed = True
    
    for addr in test_addresses:
        data, cycles = await execute_load(dut, addr)
        expected = expected_data(addr)
        
        match = data == expected
        if not match:
            passed = False
        
        status = "PASS" if match else "FAIL"
        logger.log_message(f"  LDR addr={addr}: data=0x{data:04X} (exp=0x{expected:04X}), cycles={cycles} [{status}]")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "LSU load basic test failed"


@cocotb.test()
async def test_lsu_store_basic(dut):
    """Test basic store operation."""
    logger = await setup_lsu_test(dut, "lsu_store_basic")
    
    test_cases = [
        (10, 0x1234),
        (20, 0xABCD),
        (30, 0x5555),
    ]
    
    passed = True
    
    for addr, data in test_cases:
        # Store data
        success, cycles = await execute_store(dut, addr, data)
        
        if not success:
            passed = False
            logger.log_message(f"  STR addr={addr}, data=0x{data:04X}: TIMEOUT [{cycles} cycles]")
            continue
        
        logger.log_message(f"  STR addr={addr}, data=0x{data:04X}: completed in {cycles} cycles")
        
        # Verify by loading back
        read_data, _ = await execute_load(dut, addr)
        
        match = read_data == data
        if not match:
            passed = False
        
        status = "PASS" if match else "FAIL"
        logger.log_message(f"    Verify: read=0x{read_data:04X}, exp=0x{data:04X} [{status}]")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "LSU store basic test failed"


@cocotb.test()
async def test_lsu_state_machine(dut):
    """Test LSU state machine transitions."""
    logger = await setup_lsu_test(dut, "lsu_state_machine")
    
    # Initial state should be IDLE
    initial_state = int(dut.lsu_state.value)
    logger.log_message(f"  Initial state: {initial_state} (expect {LSU_IDLE})")
    
    # Set up a load
    dut.rs.value = 50
    dut.mem_read_enable.value = 1
    
    passed = True
    states_seen = []
    
    # Go to REQUEST state
    dut.core_state.value = STATE_REQUEST
    await RisingEdge(dut.clk)
    states_seen.append(int(dut.lsu_state.value))
    
    # Monitor state transitions
    for _ in range(10):
        await RisingEdge(dut.clk)
        state = int(dut.lsu_state.value)
        states_seen.append(state)
        
        if state == LSU_DONE:
            break
    
    logger.log_message(f"  States observed: {states_seen}")
    
    # Should see: IDLE -> REQUESTING -> WAITING -> DONE
    expected_transition = [LSU_IDLE, LSU_REQUESTING, LSU_WAITING, LSU_DONE]
    
    # Check that all expected states were seen in order
    state_idx = 0
    for state in states_seen:
        if state_idx < len(expected_transition) and state == expected_transition[state_idx]:
            state_idx += 1
    
    if state_idx < len(expected_transition):
        passed = False
        logger.log_message(f"  Missing states in transition!")
    
    # Reset LSU
    dut.core_state.value = STATE_UPDATE
    await RisingEdge(dut.clk)
    dut.core_state.value = STATE_IDLE
    dut.mem_read_enable.value = 0
    await RisingEdge(dut.clk)
    
    final_state = int(dut.lsu_state.value)
    if final_state != LSU_IDLE:
        passed = False
        logger.log_message(f"  Final state not IDLE: {final_state}")
    else:
        logger.log_message(f"  State machine reset to IDLE: PASS")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "LSU state machine test failed"


@cocotb.test()
async def test_lsu_load_q115_values(dut):
    """Test loading Q1.15 fixed-point values."""
    logger = await setup_lsu_test(dut, "lsu_load_q115")
    
    # First, store some Q1.15 values
    q115_values = [
        (0, float_to_q115(0.5)),
        (1, float_to_q115(-0.25)),
        (2, float_to_q115(0.125)),
        (3, float_to_q115(-0.999)),
    ]
    
    logger.log_message("Storing Q1.15 values:")
    for addr, val in q115_values:
        await execute_store(dut, addr, val)
        logger.log_message(f"  Stored {format_q115(val)} at addr {addr}")
    
    # Now load them back
    logger.log_message("\nLoading Q1.15 values:")
    passed = True
    
    for addr, expected in q115_values:
        data, _ = await execute_load(dut, addr)
        
        match = data == expected
        if not match:
            passed = False
        
        status = "PASS" if match else "FAIL"
        logger.log_message(f"  addr={addr}: {format_q115(data)} (exp={format_q115(expected)}) [{status}]")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "LSU load Q1.15 test failed"


@cocotb.test()
async def test_lsu_sequential_access(dut):
    """Test sequential memory access pattern."""
    logger = await setup_lsu_test(dut, "lsu_sequential")
    
    # Store a sequence of values
    base_addr = 100
    num_values = 10
    
    logger.log_message(f"Sequential store to addresses {base_addr}-{base_addr + num_values - 1}")
    
    for i in range(num_values):
        await execute_store(dut, base_addr + i, 0x1000 + i)
    
    logger.log_message("Sequential load and verify:")
    passed = True
    
    for i in range(num_values):
        data, _ = await execute_load(dut, base_addr + i)
        expected = 0x1000 + i
        
        if data != expected:
            passed = False
            logger.log_message(f"  addr={base_addr + i}: MISMATCH {data} != {expected}")
    
    if passed:
        logger.log_message("  All values match!")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "LSU sequential access test failed"


@cocotb.test()
async def test_lsu_random_access(dut):
    """Test random memory access pattern."""
    logger = await setup_lsu_test(dut, "lsu_random")
    
    random.seed(42)
    num_ops = 20
    
    # Store random values at random addresses
    stored = {}
    
    logger.log_message(f"Random store operations:")
    for _ in range(num_ops):
        addr = random.randint(0, 255)
        data = random.randint(0, 0xFFFF)
        await execute_store(dut, addr, data)
        stored[addr] = data
    
    logger.log_message(f"  Stored {len(stored)} unique addresses")
    
    # Read back and verify
    logger.log_message("Random load and verify:")
    passed = True
    
    for addr, expected in stored.items():
        data, _ = await execute_load(dut, addr)
        
        if data != expected:
            passed = False
            logger.log_message(f"  addr={addr}: MISMATCH 0x{data:04X} != 0x{expected:04X}")
    
    if passed:
        logger.log_message(f"  All {len(stored)} values match!")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "LSU random access test failed"


@cocotb.test()
async def test_lsu_timing(dut):
    """Test LSU operation timing."""
    logger = await setup_lsu_test(dut, "lsu_timing")
    
    # Measure load timing
    _, load_cycles = await execute_load(dut, 50)
    logger.log_message(f"  Load cycles: {load_cycles}")
    
    # Measure store timing
    _, store_cycles = await execute_store(dut, 60, 0xBEEF)
    logger.log_message(f"  Store cycles: {store_cycles}")
    
    # Both should complete in reasonable time
    passed = load_cycles < 10 and store_cycles < 10
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "LSU timing test failed"


@cocotb.test()
async def test_lsu_memory_interface(dut):
    """Test memory interface signals via store-then-load roundtrip."""
    logger = await setup_lsu_test(dut, "lsu_memory_interface")
    
    passed = True
    
    # Test store-then-load roundtrip at multiple addresses
    test_cases = [
        (200, 0x1234, "Address 200"),
        (201, 0xABCD, "Address 201"),
        (202, 0x5555, "Address 202"),
        (203, 0xCAFE, "Address 203"),
    ]
    
    for addr, value, desc in test_cases:
        await execute_store(dut, addr, value)
        readback, _ = await execute_load(dut, addr)
        
        if readback == value:
            logger.log_message(f"  {desc}: wrote=0x{value:04X}, read=0x{readback:04X} [PASS]")
        else:
            passed = False
            logger.log_message(f"  {desc}: wrote=0x{value:04X}, read=0x{readback:04X} [FAIL]")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "LSU memory interface test failed"

