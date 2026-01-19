"""
Cache Unit Tests for Atreides GPU

Tests the instruction cache with:
- Cache hit (single cycle)
- Cache miss (multi-cycle fetch)
- Cache replacement
- Sequential access patterns
- Random access patterns
- Tag/index verification
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer
import random
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from helpers.logger import GPULogger


# Cache parameters (must match testbench)
ADDR_BITS = 8
DATA_BITS = 16
CACHE_SIZE = 16
INDEX_BITS = 4  # log2(CACHE_SIZE)
TAG_BITS = ADDR_BITS - INDEX_BITS


async def setup_cache_test(dut, test_name: str, clock_period_ns: int = 10) -> GPULogger:
    """Set up cache test environment."""
    logger = GPULogger(test_name, log_dir="test/results")
    logger.set_verbose(True)
    
    logger.log_section(f"Cache Unit Test: {test_name}")
    
    # Start clock
    clock = Clock(dut.clk, clock_period_ns, units="ns")
    cocotb.start_soon(clock.start())
    
    # Initialize signals
    dut.reset.value = 1
    dut.read_valid.value = 0
    dut.read_address.value = 0
    
    # Wait for reset
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 2)
    
    return logger


async def read_cache(dut, address: int, max_cycles: int = 20) -> tuple:
    """
    Read from cache and return data and cycle count.
    
    Args:
        dut: Device under test
        address: Memory address to read
        max_cycles: Maximum cycles to wait
        
    Returns:
        (data, cycles, hit) - read data, cycles taken, whether it was a hit
    """
    # Ensure clean state - deassert valid first
    dut.read_valid.value = 0
    await RisingEdge(dut.clk)
    
    # Start new request
    dut.read_address.value = address
    dut.read_valid.value = 1
    
    cycles = 0
    while cycles < max_cycles:
        await RisingEdge(dut.clk)
        cycles += 1
        
        if int(dut.read_ready.value) == 1:
            data = int(dut.read_data.value)
            dut.read_valid.value = 0
            
            # Wait for ready to deassert before next operation
            await RisingEdge(dut.clk)
            while int(dut.read_ready.value) == 1:
                await RisingEdge(dut.clk)
            
            # 2 cycles = hit, more = miss (accounting for state machine overhead)
            hit = cycles <= 3
            return data, cycles, hit
    
    dut.read_valid.value = 0
    return None, cycles, False


def expected_data(addr: int) -> int:
    """Get expected data from backing memory pattern."""
    return addr * 2 + 1


def get_index(addr: int) -> int:
    """Extract cache index from address."""
    return addr & ((1 << INDEX_BITS) - 1)


def get_tag(addr: int) -> int:
    """Extract cache tag from address."""
    return addr >> INDEX_BITS


@cocotb.test()
async def test_cache_miss(dut):
    """Test cache miss on cold cache."""
    logger = await setup_cache_test(dut, "cache_miss")
    
    test_addresses = [0, 5, 10, 15]
    passed = True
    
    logger.log_message("Testing cache misses (cold cache)")
    
    for addr in test_addresses:
        data, cycles, hit = await read_cache(dut, addr)
        expected = expected_data(addr)
        
        data_match = data == expected
        is_miss = not hit  # Should be a miss
        
        if not data_match or hit:
            passed = False
        
        status = "PASS" if (data_match and is_miss) else "FAIL"
        logger.log_message(f"  Addr={addr}: data={data} (exp={expected}), cycles={cycles}, hit={hit} [{status}]")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Cache miss test failed"


@cocotb.test()
async def test_cache_hit(dut):
    """Test cache hit after filling."""
    logger = await setup_cache_test(dut, "cache_hit")
    
    test_addresses = [0, 1, 2, 3]
    passed = True
    
    logger.log_message("Phase 1: Fill cache (misses expected)")
    
    # First pass: fill cache
    for addr in test_addresses:
        data, cycles, hit = await read_cache(dut, addr)
        logger.log_message(f"  Fill addr={addr}: cycles={cycles}, hit={hit}")
    
    logger.log_message("\nPhase 2: Read again (hits expected)")
    
    # Second pass: should be hits
    for addr in test_addresses:
        data, cycles, hit = await read_cache(dut, addr)
        expected = expected_data(addr)
        
        data_match = data == expected
        is_hit = hit  # Should be a hit this time
        
        if not data_match or not is_hit:
            passed = False
        
        status = "PASS" if (data_match and is_hit) else "FAIL"
        logger.log_message(f"  Addr={addr}: data={data} (exp={expected}), cycles={cycles}, hit={hit} [{status}]")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Cache hit test failed"


@cocotb.test()
async def test_cache_replacement(dut):
    """Test cache line replacement (same index, different tag)."""
    logger = await setup_cache_test(dut, "cache_replacement")
    
    # Two addresses with same index but different tags
    # Index = addr & 0xF, Tag = addr >> 4
    addr1 = 5         # index=5, tag=0
    addr2 = 5 + 16    # index=5, tag=1
    addr3 = 5 + 32    # index=5, tag=2
    
    logger.log_message(f"Testing cache replacement at index {get_index(addr1)}")
    logger.log_message(f"  addr1={addr1} (index={get_index(addr1)}, tag={get_tag(addr1)})")
    logger.log_message(f"  addr2={addr2} (index={get_index(addr2)}, tag={get_tag(addr2)})")
    logger.log_message(f"  addr3={addr3} (index={get_index(addr3)}, tag={get_tag(addr3)})")
    
    passed = True
    
    # Load addr1
    data1, cycles1, hit1 = await read_cache(dut, addr1)
    logger.log_message(f"\n  Load addr1: cycles={cycles1}, hit={hit1}")
    
    # Read addr1 again (should hit)
    data1b, cycles1b, hit1b = await read_cache(dut, addr1)
    if not hit1b:
        passed = False
    logger.log_message(f"  Read addr1 again: cycles={cycles1b}, hit={hit1b} [should hit]")
    
    # Load addr2 (replaces addr1)
    data2, cycles2, hit2 = await read_cache(dut, addr2)
    if hit2:
        passed = False
    logger.log_message(f"  Load addr2: cycles={cycles2}, hit={hit2} [should miss]")
    
    # Read addr1 again (should miss now)
    data1c, cycles1c, hit1c = await read_cache(dut, addr1)
    if hit1c:
        passed = False
    logger.log_message(f"  Read addr1 again: cycles={cycles1c}, hit={hit1c} [should miss, was replaced]")
    
    # Verify data correctness
    if data1 != expected_data(addr1) or data2 != expected_data(addr2):
        passed = False
        logger.log_message(f"\n  Data mismatch!")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Cache replacement test failed"


@cocotb.test()
async def test_cache_sequential(dut):
    """Test sequential address access pattern."""
    logger = await setup_cache_test(dut, "cache_sequential")
    
    passed = True
    hit_count = 0
    miss_count = 0
    
    logger.log_message("Sequential read pattern (0-31)")
    
    # First pass: sequential read
    for addr in range(32):
        data, cycles, hit = await read_cache(dut, addr)
        expected = expected_data(addr)
        
        if data != expected:
            passed = False
            logger.log_message(f"  Addr={addr}: data MISMATCH {data} != {expected}")
        
        if hit:
            hit_count += 1
        else:
            miss_count += 1
    
    logger.log_message(f"\n  First pass: {hit_count} hits, {miss_count} misses")
    
    # Second pass: repeat first 16 addresses (should hit for cached ones)
    hit_count2 = 0
    for addr in range(16):
        data, cycles, hit = await read_cache(dut, addr)
        if hit:
            hit_count2 += 1
    
    logger.log_message(f"  Second pass (0-15): {hit_count2}/16 hits")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Cache sequential test failed"


@cocotb.test()
async def test_cache_random(dut):
    """Test random address access pattern."""
    logger = await setup_cache_test(dut, "cache_random")
    
    random.seed(42)
    num_accesses = 50
    passed = True
    hit_count = 0
    
    logger.log_message(f"Random read pattern ({num_accesses} accesses)")
    
    for i in range(num_accesses):
        addr = random.randint(0, 255)
        data, cycles, hit = await read_cache(dut, addr)
        expected = expected_data(addr)
        
        if data != expected:
            passed = False
            logger.log_message(f"  [{i}] Addr={addr}: MISMATCH {data} != {expected}")
        
        if hit:
            hit_count += 1
    
    hit_rate = hit_count / num_accesses * 100
    logger.log_message(f"\n  Total: {hit_count}/{num_accesses} hits ({hit_rate:.1f}%)")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Cache random test failed"


@cocotb.test()
async def test_cache_locality(dut):
    """Test temporal locality (repeated access to same addresses)."""
    logger = await setup_cache_test(dut, "cache_locality")
    
    # Working set that fits in cache
    working_set = [0, 1, 2, 3, 4, 5, 6, 7]
    
    passed = True
    
    logger.log_message("Testing temporal locality")
    logger.log_message(f"Working set: {working_set}")
    
    # Warm up cache
    logger.log_message("\n  Warmup phase:")
    for addr in working_set:
        data, cycles, hit = await read_cache(dut, addr)
        logger.log_message(f"    Addr={addr}: cycles={cycles}, hit={hit}")
    
    # Access pattern with good temporal locality
    logger.log_message("\n  Locality test (multiple passes):")
    hit_count = 0
    total = 0
    
    for _ in range(3):
        for addr in working_set:
            data, cycles, hit = await read_cache(dut, addr)
            if hit:
                hit_count += 1
            total += 1
    
    hit_rate = hit_count / total * 100
    logger.log_message(f"  {hit_count}/{total} hits ({hit_rate:.1f}%)")
    
    # Should have very high hit rate after warmup
    if hit_rate < 90:
        passed = False
        logger.log_message("  WARNING: Hit rate too low for good temporal locality!")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Cache locality test failed"


@cocotb.test()
async def test_cache_cycle_timing(dut):
    """Test that hit/miss cycle counts are correct."""
    logger = await setup_cache_test(dut, "cache_cycle_timing")
    
    passed = True
    
    logger.log_message("Testing cache timing")
    
    # Cold miss - should take multiple cycles
    addr = 100
    _, cycles_miss, hit = await read_cache(dut, addr)
    logger.log_message(f"  Cold miss at addr={addr}: {cycles_miss} cycles, hit={hit}")
    
    if cycles_miss < 4:
        passed = False
        logger.log_message("    ERROR: Cold miss should take 4+ cycles")
    
    # Hot hit - should take fewer cycles
    _, cycles_hit, hit = await read_cache(dut, addr)
    logger.log_message(f"  Hot hit at addr={addr}: {cycles_hit} cycles, hit={hit}")
    
    if cycles_hit > 3:
        passed = False
        logger.log_message("    ERROR: Hot hit should take 3 or fewer cycles")
    
    # Verify hit is faster than miss
    if cycles_hit >= cycles_miss:
        passed = False
        logger.log_message("    ERROR: Hit should be faster than miss")
    
    logger.log_message(f"\n  Miss latency: {cycles_miss} cycles")
    logger.log_message(f"  Hit latency: {cycles_hit} cycles")
    if cycles_hit > 0:
        logger.log_message(f"  Speedup: {cycles_miss / cycles_hit:.1f}x")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Cache cycle timing test failed"

