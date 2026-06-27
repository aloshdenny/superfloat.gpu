"""
Test Setup Utilities for Atreides GPU Simulation

Provides helpers for configuring and running GPU tests.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer

from .memory import init_program_memory, init_data_memory
from .logger import GPULogger


async def setup_test(dut, test_name: str, program: list, data: list = None, 
                     thread_count: int = 1, clock_period_ns: int = 10,
                     verbose: bool = True) -> GPULogger:
    """
    Set up a GPU test.
    
    Args:
        dut: cocotb DUT handle
        test_name: Name of the test
        program: List of 16-bit instructions
        data: Optional list of initial data memory values
        thread_count: Number of threads to launch
        clock_period_ns: Clock period in nanoseconds
        verbose: Enable console output
        
    Returns:
        GPULogger instance for trace logging
    """
    # Create logger
    logger = GPULogger(test_name)
    logger.set_verbose(verbose)
    
    logger.log_section(f"Test Setup: {test_name}")
    logger.log_message(f"Thread count: {thread_count}")
    logger.log_message(f"Program size: {len(program)} instructions")
    
    # Start clock
    clock = Clock(dut.clk, clock_period_ns, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Initialize signals
    dut.reset.value = 1
    dut.start.value = 0
    dut.thread_count.value = thread_count
    
    # Wait for reset
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 2)
    
    # Initialize program memory (async - uses write port)
    await init_program_memory(dut, program)
    logger.log_message(f"Loaded {len(program)} instructions to program memory")
    
    # Debug: Verify first few instructions were loaded
    try:
        for i in range(min(3, len(program))):
            val = int(dut.program_memory[i].value)
            logger.log_message(f"  prog_mem[{i}] = 0x{val:04X} (expected 0x{program[i]:04X})")
    except Exception as e:
        logger.log_message(f"  Warning: Could not verify program memory: {e}")
    
    # Initialize data memory
    if data:
        init_data_memory(dut, data)
        logger.log_message(f"Loaded {len(data)} values to data memory")
        logger.log_memory({i: data[i] for i in range(len(data))}, 0, len(data), "Initial Data Memory")
    
    await ClockCycles(dut.clk, 2)
    
    return logger


async def run_kernel(dut, logger: GPULogger, max_cycles: int = 1000, 
                     trace_interval: int = 1) -> int:
    """
    Run the GPU kernel until completion.
    
    Args:
        dut: cocotb DUT handle
        logger: GPULogger instance
        max_cycles: Maximum cycles to run
        trace_interval: Log trace every N cycles (0 to disable)
        
    Returns:
        Number of cycles executed
    """
    logger.log_section("Kernel Execution")
    
    # Start kernel - keep start HIGH during entire execution
    dut.start.value = 1
    
    cycle = 0
    done_seen = False
    while cycle < max_cycles:
        await RisingEdge(dut.clk)
        cycle += 1
        
        # Log trace if enabled
        if trace_interval > 0 and cycle % trace_interval == 0:
            cores = get_core_states(dut)
            logger.log_cycle(cycle, cores)
        
        # Check if done
        try:
            done_val = int(dut.done.value)
            if done_val == 1 and not done_seen:
                done_seen = True
                logger.log_message(f"\nKernel completed in {cycle} cycles")
                break
        except:
            pass
    
    if not done_seen:
        logger.log_message(f"\nWARNING: Reached max cycles ({max_cycles})")
    
    # Deassert start after completion
    dut.start.value = 0
    
    return cycle


def get_core_states(dut) -> list:
    """
    Get the current state of all cores for trace logging.
    
    Args:
        dut: cocotb DUT handle (tb_gpu testbench)
        
    Returns:
        List of core state dictionaries
    """
    cores = []
    num_cores = 1  # Single core in testbench
    threads_per_block = 4
    
    for core_idx in range(num_cores):
        core_data = {'threads': []}
        
        # Access the core through the GPU instance in the testbench
        # tb_gpu -> gpu_inst -> cores[i] -> core_instance
        try:
            # Try to access core state from the nested hierarchy
            gpu = dut.gpu_inst
            core = gpu.cores[core_idx].core_instance
            scheduler = core.scheduler_instance
            fetcher = core.fetcher_instance
            
            # Get shared core-level state
            core_state = int(scheduler.core_state.value)
            fetcher_state = int(fetcher.fetcher_state.value)
            instruction = int(core.instruction.value)
            current_pc = int(scheduler.current_pc.value)
            block_id = int(gpu.dispatch_instance.core_block_id[core_idx].value)
            
            for thread_idx in range(threads_per_block):
                thread_block = core.threads[thread_idx]
                
                # Get per-thread state
                try:
                    lsu_state = int(thread_block.lsu_instance.state.value)
                except:
                    lsu_state = 0
                
                try:
                    alu_out = int(thread_block.alu_instance.out.value)
                except:
                    alu_out = 0
                
                try:
                    fma_out = int(thread_block.fma_instance.result.value)
                except:
                    fma_out = None
                
                thread_data = {
                    'thread_id': thread_idx,
                    'pc': current_pc,
                    'instruction': instruction,
                    'core_state': core_state,
                    'fetcher_state': fetcher_state,
                    'lsu_state': lsu_state,
                    'registers': get_thread_registers(core, thread_idx),
                    'block_idx': block_id,
                    'block_dim': threads_per_block,
                    'thread_idx': thread_idx,
                    'rs_val': 0,
                    'rt_val': 0,
                    'alu_out': alu_out,
                    'fma_out': fma_out
                }
                core_data['threads'].append(thread_data)
                
        except Exception as e:
            # Simplified fallback - try direct signal access
            try:
                # Try simplified paths
                core_state = int(dut.gpu_inst.cores[0].core_instance.scheduler_instance.core_state.value)
            except:
                core_state = 0
            
            for thread_idx in range(threads_per_block):
                thread_data = {
                    'thread_id': thread_idx,
                    'pc': 0,
                    'instruction': 0,
                    'core_state': core_state,
                    'fetcher_state': 0,
                    'lsu_state': 0,
                    'registers': [0] * 13,
                    'block_idx': 0,
                    'block_dim': threads_per_block,
                    'thread_idx': thread_idx,
                    'rs_val': 0,
                    'rt_val': 0,
                    'alu_out': 0,
                    'fma_out': None
                }
                core_data['threads'].append(thread_data)
        
        cores.append(core_data)
    
    return cores


def get_thread_registers(core, thread_idx: int) -> list:
    """
    Get register values for a specific thread.
    
    Args:
        core: Core DUT handle
        thread_idx: Thread index
        
    Returns:
        List of 13 register values
    """
    regs = []
    try:
        for i in range(13):
            val = int(core.register_files[thread_idx].registers[i].value)
            regs.append(val)
    except:
        regs = [0] * 13
    return regs

