"""
External Memory Model — Chip-Pin-Level Bus-Functional Model

Emulates the off-chip SRAM that `tt_um_aloshdenny_gpu` expects on its
time-multiplexed uio address/data bus. This lets cocotb tests drive the real
chip top-level (through ui_in/uo_out/uio_in/uio_out/uio_oe) instead of poking
gpu.sv's internals directly, so the exact same test can run against the RTL
*and* the post-synthesis gate-level netlist (GATES=yes).

Protocol (mirrors `tt_um_aloshdenny_gpu.sv` §4, "Time-Multiplexed External
Memory Interface Controller" -- see also info.yaml's pinout section):

  uo_out[0] = done
  uo_out[1] = mem_we      (write strobe, held for 2 cycles)
  uo_out[2] = mem_re      (read strobe, held for 2 cycles)
  uo_out[3] = ale         (address latch enable, held for 3 cycles)
  uo_out[4] = mem_sel     (0 = program memory, 1 = data memory)
  uio[7:0]  = time-multiplexed address/data bus

Address phase (3 consecutive cycles with ale high), one byte per cycle:
  byte0 = addr[7:0]
  byte1 = addr[15:8]
  byte2 = {mem_sel, is_write, 3'b000, addr[18:16]}

Data phase:
  - Write (mem_we high for DATA0+DATA1): DUT drives write_data[7:0] then
    write_data[15:8].
  - Read: DUT holds mem_re for DATA0+DATA1, then samples on ACK with
    mem_re already low:
      DATA1 posedge: latches uio_in as low byte
      ACK   posedge: samples uio_in as high byte
    So the model must keep the high byte on uio_in through the ACK cycle.

The BFM runs on FallingEdge so DUT outputs are stable to sample and so
uio_in writes are applied well before the next RisingEdge sample (cocotb
RisingEdge resumes in the ReadOnly region where signal writes are deferred).
"""

import cocotb
from cocotb.triggers import FallingEdge

PROGRAM_MEM_ADDR_BITS = 9
DATA_MEM_ADDR_BITS = 19

_PROGRAM_MASK = (1 << PROGRAM_MEM_ADDR_BITS) - 1
_DATA_MASK = (1 << DATA_MEM_ADDR_BITS) - 1


class ExternalMemoryModel:
    """Bus-functional model of the external program/data SRAM."""

    def __init__(self, dut, program=None, data=None):
        self.dut = dut
        self.program_mem = [0] * (1 << PROGRAM_MEM_ADDR_BITS)
        # Sparse-ish: still allocate full space so address indexing matches RTL,
        # but only the first few dozen words are touched by the matmul kernel.
        self.data_mem = [0] * (1 << DATA_MEM_ADDR_BITS)

        if program:
            for addr, instr in enumerate(program):
                self.program_mem[addr] = instr & 0xFFFF
        if data:
            for addr, value in enumerate(data):
                self.data_mem[addr] = value & 0xFFFF

        self._ale_cycle = 0
        self._addr_bytes = [0, 0, 0]
        self._latched_addr = 0
        self._latched_mem_sel = 0

        self._we_cycle = 0
        self._wdata_bytes = [0, 0]

        self._re_cycle = 0
        self._pending_hi = 0

        self._task = None

    def start(self):
        """Launch the background coroutine that services the bus."""
        self._task = cocotb.start_soon(self._run())
        return self._task

    def stop(self):
        if self._task is not None:
            self._task.cancel()
            self._task = None

    async def _run(self):
        dut = self.dut
        dut.uio_in.value = 0
        while True:
            # Mid-cycle: DUT registered outputs from the last posedge are
            # stable, and writes here land before the next posedge sample.
            await FallingEdge(dut.clk)
            uo = int(dut.uo_out.value)
            mem_we = (uo >> 1) & 1
            mem_re = (uo >> 2) & 1
            ale = (uo >> 3) & 1
            uio_out = int(dut.uio_out.value)

            if ale:
                self._addr_bytes[self._ale_cycle] = uio_out
                self._ale_cycle += 1
                if self._ale_cycle == 3:
                    byte0, byte1, byte2 = self._addr_bytes
                    self._latched_mem_sel = (byte2 >> 7) & 1
                    addr_hi = byte2 & 0x7
                    self._latched_addr = (addr_hi << 16) | (byte1 << 8) | byte0
                    self._ale_cycle = 0
            else:
                self._ale_cycle = 0

            if mem_we:
                self._wdata_bytes[self._we_cycle] = uio_out
                self._we_cycle += 1
                if self._we_cycle == 2:
                    value = self._wdata_bytes[0] | (self._wdata_bytes[1] << 8)
                    self._commit_write(value)
                    self._we_cycle = 0
            else:
                self._we_cycle = 0

            if mem_re:
                if self._re_cycle == 0:
                    # After DATA0 posedge: drive lo so DATA1 latches it.
                    value = self._read_value()
                    dut.uio_in.value = value & 0xFF
                    self._pending_hi = (value >> 8) & 0xFF
                    self._re_cycle = 1
                else:
                    # After DATA1 posedge: drive hi so ACK samples it.
                    dut.uio_in.value = self._pending_hi
                    self._re_cycle = 2
            elif self._re_cycle == 2:
                # After ACK posedge: hi was sampled; release the bus.
                self._re_cycle = 0
                dut.uio_in.value = 0
            else:
                self._re_cycle = 0
                dut.uio_in.value = 0

    def _commit_write(self, value):
        if self._latched_mem_sel == 0:
            self.program_mem[self._latched_addr & _PROGRAM_MASK] = value
        else:
            self.data_mem[self._latched_addr & _DATA_MASK] = value

    def _read_value(self):
        if self._latched_mem_sel == 0:
            return self.program_mem[self._latched_addr & _PROGRAM_MASK]
        return self.data_mem[self._latched_addr & _DATA_MASK]
