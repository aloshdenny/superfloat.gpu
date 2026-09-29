"""
Chip-level tests for superfloat_openframe through its pins.

A cocotb host holds program and data memory and answers the two-phase pin
handshake (REQ toggles, host sets ACK = REQ) after a random 0-4 cycle delay, so
the ACK synchronizer and the round-robin arbiter see realistic timing. Kernels
are launched the way a board would: thread count on bus_in[7:0], raise START,
wait for DONE, lower START.

The kernels and golden models are shared with test_openframe_tile.py.
"""

import os
import random
import sys

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge

sys.path.insert(0, os.path.dirname(__file__))
from helpers.number_format import NAMES, number_format, fp_format
from test_openframe_tile import (
    N, NUM_TILES, BLOCK_STRIDE, A_OFF, B_OFF, C_OFF, SCRATCH_BASE, SCRATCH_OUT,
    build_systolic8_program, build_scratchpad_program, expected_block, random_operand,
)

PROGRAM_WORDS = 512


class Host:
    """Program/data memory behind the pin bus."""

    def __init__(self, dut, seed: int):
        self.dut = dut
        self.rng = random.Random(seed)
        self.program = [0] * PROGRAM_WORDS
        self.data = {}
        self.reads = {0: 0, 1: 0}
        self.writes = 0
        self.thread_count = 0
        self.idle = True           # bus_in carries the thread count between kernels
        self._write_addr = None

    def load_program(self, words):
        assert len(words) <= PROGRAM_WORDS
        self.program = list(words) + [0] * (PROGRAM_WORDS - len(words))

    async def serve(self):
        dut = self.dut
        dut.bus_ack.value = 0
        dut.bus_in.value = 0
        while True:
            await FallingEdge(dut.clk)
            if self.idle:
                dut.bus_in.value = self.thread_count
            if not dut.bus_req.value.is_resolvable:
                continue                        # before reset reaches the bus
            req = int(dut.bus_req.value)
            if req == int(dut.bus_ack.value):
                continue
            for _ in range(self.rng.randint(0, 4)):
                await FallingEdge(dut.clk)
            # Uninitialized scratchpad words simulate as X; keep them as None.
            word = int(dut.bus_out.value) if dut.bus_out.value.is_resolvable else None
            sel, we, beat = int(dut.bus_sel.value), int(dut.bus_we.value), int(dut.bus_beat.value)
            if we:
                if beat == 0:
                    assert word is not None, "write address contains X"
                    self._write_addr = word
                else:
                    assert sel == 1, "program memory is read-only"
                    self.data[self._write_addr] = word
                    self.writes += 1
            else:
                assert word is not None, "read address contains X"
                value = self.program[word % PROGRAM_WORDS] if sel == 0 else self.data.get(word, 0)
                dut.bus_in.value = value
                self.reads[sel] += 1
                await FallingEdge(dut.clk)      # data settles before ACK moves
            dut.bus_ack.value = req


async def chip_reset(dut):
    dut.rst_n.value = 0
    dut.start.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)


async def launch(dut, host: Host, thread_count: int, max_cycles: int) -> int:
    host.thread_count = thread_count
    host.idle = True
    await ClockCycles(dut.clk, 3)
    dut.start.value = 1
    await ClockCycles(dut.clk, 4)       # thread count is latched two cycles after START syncs in
    host.idle = False
    active_seen = 0
    for cycle in range(max_cycles):
        await RisingEdge(dut.clk)
        active_seen |= int(dut.core_active.value)
        if int(dut.done.value):
            break
    else:
        raise AssertionError(f"DONE not seen within {max_cycles} cycles")
    dut.start.value = 0
    await ClockCycles(dut.clk, 4)
    assert int(dut.done.value) == 0, "DONE must drop with START"
    return cycle, active_seen


def systolic_data(seed: int, fmt=None):
    rng = random.Random(seed)
    data, expected = {}, {}
    for b in range(NUM_TILES):
        A = [[random_operand(rng, fmt) for _ in range(N)] for _ in range(N)]
        B = [[random_operand(rng, fmt) for _ in range(N)] for _ in range(N)]
        base = b * BLOCK_STRIDE
        for i in range(N):
            for k in range(N):
                data[base + A_OFF + i * N + k] = A[i][k]
                data[base + B_OFF + i * N + k] = B[i][k]
        expected[b] = expected_block(A, B, fmt)
    return data, expected


def check_systolic(host: Host, expected: dict):
    bad = []
    for b in range(NUM_TILES):
        base = b * BLOCK_STRIDE + C_OFF
        for c in range(N * N):
            got = host.data.get(base + c, 0)
            if got != expected[b][c]:
                bad.append((b, c, got, expected[b][c]))
    assert not bad, f"{len(bad)} mismatching cells, first: {bad[:4]}"


def check_scratchpad(host: Host):
    for b in range(NUM_TILES):
        own = [host.data.get(SCRATCH_OUT + b * 16 + t, 0) for t in range(N)]
        nbr = [host.data.get(SCRATCH_OUT + b * 16 + N + t, 0) for t in range(N)]
        assert own == [b * 16 + t + 1 for t in range(N)], f"tile {b} own slots {own}"
        assert nbr == [b * 16 + (t + 1) % N + 1 for t in range(N)], f"tile {b} neighbour slots {nbr}"
    leaked = [a for a in host.data if SCRATCH_BASE <= a <= 0xFFFF]
    assert not leaked, f"scratchpad addresses reached the pins: {leaked[:4]}"


@cocotb.test()
async def test_chip_systolic8_then_scratchpad(dut):
    """Two kernels back to back through the pins, no chip reset in between."""
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    host = Host(dut, seed=0x0F)
    cocotb.start_soon(host.serve())
    await chip_reset(dut)

    fmt_id = number_format(dut)
    dut._log.info(f"number format: {NAMES[fmt_id]}")
    host.data, expected = systolic_data(seed=0x8A8, fmt=fp_format(fmt_id))
    host.load_program(build_systolic8_program())
    cycles, active = await launch(dut, host, thread_count=N * NUM_TILES, max_cycles=400000)
    dut._log.info(f"systolic8 via pins: {cycles} cycles, program reads {host.reads[0]}, "
                  f"data reads {host.reads[1]}, writes {host.writes}, tiles seen active {active:04b}")
    assert active == (1 << NUM_TILES) - 1, f"not every tile ran: {active:04b}"
    check_systolic(host, expected)

    host.data = {}
    host.load_program(build_scratchpad_program())
    cycles, active = await launch(dut, host, thread_count=N * NUM_TILES, max_cycles=200000)
    dut._log.info(f"scratchpad via pins: {cycles} cycles, tiles seen active {active:04b}")
    check_scratchpad(host)


@cocotb.test()
async def test_chip_partial_launch(dut):
    """20 threads: two full blocks and a 4-thread block; idle tile must stay idle."""
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    host = Host(dut, seed=0x33)
    cocotb.start_soon(host.serve())
    await chip_reset(dut)

    host.data = {}
    host.load_program(build_scratchpad_program())
    cycles, active = await launch(dut, host, thread_count=20, max_cycles=200000)
    assert active == 0b0111, f"expected tiles 0-2 active, saw {active:04b}"
    for b, count in ((0, 8), (1, 8), (2, 4)):
        own = [host.data.get(SCRATCH_OUT + b * 16 + t, 0) for t in range(count)]
        assert own == [b * 16 + t + 1 for t in range(count)], f"block {b}: {own}"
    assert all(host.data.get(SCRATCH_OUT + 2 * 16 + t, 0) == 0 for t in range(4, 8)), \
        "disabled threads of the partial block wrote memory"
