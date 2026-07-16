"""
Chip-Level Test for tt_um_aloshdenny_gpu — TinyTapeout gl_test entry point.

This is the module `test/Makefile` runs (COCOTB_TEST_MODULES = test) for both
plain `make` (RTL) and `GATES=yes make` (post-synthesis gate-level netlist).

It drives the actual TinyTapeout top-level through its real pins (ui_in,
uo_out, uio_in/out/oe, ena, clk, rst_n) and uses ExternalMemoryModel to emulate
the off-chip SRAM the design expects on its time-multiplexed uio bus. This
catches synthesis bugs (X-propagation, stuck-at faults, power-pin issues) that
the RTL-only unit tests in ../Makefile (test_*_unit.py, tb_gpu.sv) can't see,
because those bypass the pin protocol entirely and poke gpu.sv's internals
directly.

The kernel under test is the same 2x2 FMA-based matmul already verified at
the RTL/unit level in test_matmul.py -- reused here so the exact program and
expected results only need to be maintained in one place.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

from helpers.external_memory import ExternalMemoryModel
from helpers.q115 import q115_to_float
from test_matmul import EXPECTED_C, build_initial_data, build_matmul_program

CLOCK_PERIOD_NS = 20  # 50 MHz, matches info.yaml clock_hz
MAX_CYCLES = 20000
RESULT_TOLERANCE = 0.001


async def reset_dut(dut):
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    # tt_um_aloshdenny_gpu's internal reset synchronizer needs 2 cycles to
    # deassert gpu_reset after rst_n rises -- give it a comfortable margin.
    await ClockCycles(dut.clk, 5)


async def launch_kernel(dut, thread_count: int):
    # device_control_write_enable is level-sensitive (ui_in[6:0] != 0), so
    # thread_count must stay driven for the whole run -- matches the RTL
    # unit-test harness's behavior in helpers/setup.py.
    dut.ui_in.value = thread_count & 0x7F
    await ClockCycles(dut.clk, 2)
    dut.ui_in.value = (thread_count & 0x7F) | 0x80  # bit 7 = start


async def wait_for_done(dut, max_cycles: int) -> int:
    for cycle in range(1, max_cycles + 1):
        await RisingEdge(dut.clk)
        if int(dut.uo_out.value) & 0x1:
            return cycle
    raise TimeoutError(f"Kernel did not complete within {max_cycles} cycles")


@cocotb.test()
async def test_matmul_gate_level(dut):
    """2x2 matmul kernel, run through the real chip pins + memory protocol."""
    program = build_matmul_program()
    data = build_initial_data()

    clock = Clock(dut.clk, CLOCK_PERIOD_NS, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    mem = ExternalMemoryModel(dut, program=program, data=data)
    mem.start()

    await launch_kernel(dut, thread_count=4)

    cycles = await wait_for_done(dut, MAX_CYCLES)
    dut._log.info(f"Kernel completed in {cycles} cycles")

    dut.ui_in.value = 0  # deassert start
    await ClockCycles(dut.clk, 2)
    mem.stop()

    results_raw = mem.data_mem[8:12]
    results = [q115_to_float(r) for r in results_raw]

    dut._log.info(f"Expected: {EXPECTED_C}")
    dut._log.info(f"Actual:   {results}")

    for i, (actual, expected) in enumerate(zip(results, EXPECTED_C)):
        assert abs(actual - expected) <= RESULT_TOLERANCE, (
            f"Mismatch at C[{i}]: got {actual}, expected {expected} "
            f"(raw 0x{results_raw[i]:04X})"
        )
