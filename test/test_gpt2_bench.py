"""
GPT-2 kernel launches through the OpenFrame chip's pins (docs/gpt2_benchmark.md).

Each launch is a window of real GPT-2 operands built by gpt2/prepare.py for
the chip's NUMBER_FORMAT. The host is deterministic:
  - async bus (default): it answers every handshake after a fixed HOST_LATENCY
    cycles (0: ACK on the falling edge after REQ moves, one more for read data
    to settle);
  - sync bus (BUS_SYNC=1, selected at launch with bus_in[8]): it samples each
    beat mid-cycle and answers each read in order on the second rising edge
    after the chip raised REQ, plus HOST_LATENCY cycles, as a registered host
    clocked with the chip would. Every
stored output is checked against the bit-exact reference, and the launch's
cycles, bus reads and writes are appended to gpt2/results/<fmt>.jsonl.

  make test_gpt2_bench NUMBER_FORMAT=1 GPT2_LAUNCHES=gemv_check,gemm_check
"""
import json
import os
import sys
import time

import numpy as np

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge

sys.path.insert(0, os.path.dirname(__file__))
from helpers.number_format import NAMES, number_format       # noqa: E402
from gpt2.kernels import gemv_program, gemm_program            # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
PROGRAM_WORDS = 512


class BenchHost:
    """Program/data memory behind the pin bus, fixed response latency."""

    def __init__(self, dut, latency: int, sync: bool = False):
        self.dut = dut
        self.latency = latency
        self.sync = sync
        self.program = [0] * PROGRAM_WORDS
        self.data = {}
        self.reads = {0: 0, 1: 0}
        self.writes = 0
        self.thread_count = 0
        self.idle = True
        self._write_addr = None

    async def serve(self):
        if self.sync:
            await self.serve_sync()
            return
        dut = self.dut
        dut.bus_ack.value = 0
        dut.bus_in.value = 0
        while True:
            await FallingEdge(dut.clk)
            if self.idle:
                dut.bus_in.value = self.thread_count
            if not dut.bus_req.value.is_resolvable:
                continue
            req = int(dut.bus_req.value)
            if req == int(dut.bus_ack.value):
                continue
            for _ in range(self.latency):
                await FallingEdge(dut.clk)
            word = int(dut.bus_out.value)
            sel, we, beat = int(dut.bus_sel.value), int(dut.bus_we.value), int(dut.bus_beat.value)
            if we:
                if beat == 0:
                    self._write_addr = word
                else:
                    self.data[self._write_addr] = word
                    self.writes += 1
            else:
                dut.bus_in.value = self.program[word % PROGRAM_WORDS] if sel == 0 else self.data.get(word, 0)
                self.reads[sel] += 1
                await FallingEdge(dut.clk)
            dut.bus_ack.value = req


    async def serve_sync(self):
        dut = self.dut
        dut.bus_ack.value = 0
        dut.bus_in.value = 0
        pending = []                         # (falling edge to answer on, word)
        cycle = 0
        while True:
            await FallingEdge(dut.clk)
            cycle += 1
            if self.idle:
                dut.bus_in.value = self.thread_count | 0x100      # bus_in[8]: sync mode
                dut.bus_ack.value = 0
                continue
            if pending and pending[0][0] <= cycle:
                _, word = pending.pop(0)
                dut.bus_in.value = word
                dut.bus_ack.value = 1
            else:
                dut.bus_ack.value = 0
            if not dut.bus_req.value.is_resolvable or int(dut.bus_req.value) == 0:
                continue
            word = int(dut.bus_out.value)
            sel, we, beat = int(dut.bus_sel.value), int(dut.bus_we.value), int(dut.bus_beat.value)
            if we:
                if beat == 0:
                    self._write_addr = word
                else:
                    self.data[self._write_addr] = word
                    self.writes += 1
            else:
                value = self.program[word % PROGRAM_WORDS] if sel == 0 else self.data.get(word, 0)
                self.reads[sel] += 1
                pending.append((cycle + 1 + self.latency, value))


async def run_launch(dut, host: BenchHost, thread_count: int, max_cycles: int) -> int:
    """START to DONE, in clock cycles (the thread count is on bus_in at START)."""
    host.thread_count = thread_count
    host.idle = True
    await ClockCycles(dut.clk, 3)
    dut.start.value = 1
    await RisingEdge(dut.clk)
    cycles = 1
    while True:
        await RisingEdge(dut.clk)
        cycles += 1
        if cycles == 4:
            host.idle = False                  # thread count latched
        if cycles > 4 and int(dut.done.value):
            break
        assert cycles < max_cycles, f"DONE not seen within {max_cycles} cycles"
    dut.start.value = 0
    await ClockCycles(dut.clk, 4)
    return cycles


@cocotb.test()
async def test_gpt2_launches(dut):
    fmt = number_format(dut)
    latency = int(os.environ.get("HOST_LATENCY", "0"))
    sync = os.environ.get("BUS_SYNC", "0") == "1"
    names = [n for n in os.environ.get("GPT2_LAUNCHES", "gemv_check,gemm_check").split(",") if n]
    ldir = os.path.join(HERE, "gpt2", "launches", NAMES[fmt])
    rdir = os.path.join(HERE, "gpt2", "results")
    os.makedirs(rdir, exist_ok=True)

    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    host = BenchHost(dut, latency, sync)
    cocotb.start_soon(host.serve())
    dut.rst_n.value = 0
    dut.start.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)

    for name in names:
        z = np.load(os.path.join(ldir, name + ".npz"))
        kernel, kc, nb = str(z["kernel"]), int(z["kc"]), int(z["nb"])
        prog = gemv_program(kc) if kernel == "gemv" else gemm_program(kc)
        host.program = prog + [0] * (PROGRAM_WORDS - len(prog))
        host.data = dict(zip(z["addr"].tolist(), z["word"].tolist()))
        host.reads, host.writes = {0: 0, 1: 0}, 0
        t0 = time.time()
        cycles = await run_launch(dut, host, 8 * nb, max_cycles=20_000_000)
        wall = time.time() - t0

        bad = [(a, host.data.get(a), e) for a, e in zip(z["exp_addr"].tolist(), z["exp_word"].tolist())
               if host.data.get(a) != e]
        rec = dict(name=name, fmt=NAMES[fmt], kernel=kernel, kc=kc, nb=nb, host_latency=latency,
                   bus="sync" if sync else "async",
                   cycles=cycles, program_reads=host.reads[0], data_reads=host.reads[1],
                   writes=host.writes, outputs=len(z["exp_addr"]), mismatches=len(bad),
                   sim_seconds=round(wall, 1))
        with open(os.path.join(rdir, f"{NAMES[fmt]}.jsonl"), "a") as f:
            f.write(json.dumps(rec) + "\n")
        dut._log.info(f"{name} ({NAMES[fmt]}): {cycles} cycles, {host.reads[1]} data reads, "
                      f"{host.reads[0]} program reads, {host.writes} writes, "
                      f"{len(bad)}/{len(z['exp_addr'])} mismatches, {wall:.0f} s")
        assert not bad, f"{name}: {len(bad)} mismatches, first {[(hex(a), g, e) for a, g, e in bad[:4]]}"
