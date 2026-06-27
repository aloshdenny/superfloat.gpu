"""
Memory Initialization Utilities for Atreides GPU Simulation

Provides helpers for setting up data and program memory.
"""

from .q115 import float_to_q115


def init_data_memory(dut, data: list, start_addr: int = 0):
    """
    Initialize data memory with values.
    
    Args:
        dut: cocotb DUT handle (tb_gpu testbench)
        data: List of 16-bit values to write
        start_addr: Starting address (default 0)
    """
    for i, value in enumerate(data):
        addr = start_addr + i
        dut.data_memory[addr].value = value


def init_data_memory_q115(dut, floats: list, start_addr: int = 0):
    """
    Initialize data memory with Q1.15 values from floats.
    
    Args:
        dut: cocotb DUT handle
        floats: List of float values in range [-1.0, 1.0)
        start_addr: Starting address (default 0)
    """
    q115_values = [float_to_q115(f) for f in floats]
    init_data_memory(dut, q115_values, start_addr)


async def init_program_memory(dut, program: list):
    """
    Initialize program memory with instructions using write port.
    
    Args:
        dut: cocotb DUT handle (tb_gpu testbench)
        program: List of 16-bit instructions
    """
    from cocotb.triggers import RisingEdge
    
    for addr, instr in enumerate(program):
        dut.program_mem_write_en.value = 1
        dut.program_mem_write_addr.value = addr
        dut.program_mem_write_data_in.value = instr
        await RisingEdge(dut.clk)
    
    # Disable write
    dut.program_mem_write_en.value = 0
    await RisingEdge(dut.clk)


def read_memory(dut, addr: int) -> int:
    """
    Read a value from data memory.
    
    Args:
        dut: cocotb DUT handle
        addr: Memory address
        
    Returns:
        16-bit value at address
    """
    return int(dut.data_memory[addr].value)


def read_memory_range(dut, start_addr: int, count: int) -> list:
    """
    Read a range of values from data memory.
    
    Args:
        dut: cocotb DUT handle
        start_addr: Starting address
        count: Number of values to read
        
    Returns:
        List of 16-bit values
    """
    return [read_memory(dut, start_addr + i) for i in range(count)]


def dump_memory(dut, start_addr: int = 0, count: int = 32) -> dict:
    """
    Dump memory contents to a dictionary.
    
    Args:
        dut: cocotb DUT handle
        start_addr: Starting address
        count: Number of addresses to dump
        
    Returns:
        Dictionary of address -> value
    """
    return {addr: read_memory(dut, addr) for addr in range(start_addr, start_addr + count)}


# Assembly helpers for building programs

def asm_nop() -> int:
    """NOP instruction."""
    return 0x0000


def asm_ret() -> int:
    """RET instruction."""
    return 0xF000


def asm_const(rd: int, imm: int) -> int:
    """CONST Rd, #imm - Load 8-bit immediate."""
    return (0x9 << 12) | (rd << 8) | (imm & 0xFF)


def asm_add(rd: int, rs: int, rt: int) -> int:
    """ADD Rd, Rs, Rt - Integer add."""
    return (0x3 << 12) | (rd << 8) | (rs << 4) | rt


def asm_sub(rd: int, rs: int, rt: int) -> int:
    """SUB Rd, Rs, Rt - Integer subtract."""
    return (0x4 << 12) | (rd << 8) | (rs << 4) | rt


def asm_mul(rd: int, rs: int, rt: int) -> int:
    """MUL Rd, Rs, Rt - Integer multiply."""
    return (0x5 << 12) | (rd << 8) | (rs << 4) | rt


def asm_div(rd: int, rs: int, rt: int) -> int:
    """DIV Rd, Rs, Rt - Integer divide."""
    return (0x6 << 12) | (rd << 8) | (rs << 4) | rt


def asm_ldr(rd: int, rs: int) -> int:
    """LDR Rd, Rs - Load from memory[Rs]."""
    return (0x7 << 12) | (rd << 8) | (rs << 4)


def asm_str(rd: int, rs: int) -> int:
    """STR Rd, Rs - Store Rs to memory[Rd]."""
    return (0x8 << 12) | (rd << 8) | (rs << 4)


def asm_fma(rd: int, rs: int, rt: int) -> int:
    """FMA Rd, Rs, Rt - Q1.15 fused multiply-add: Rd = (Rs * Rt) + Rd."""
    return (0xA << 12) | (rd << 8) | (rs << 4) | rt


def asm_act(rd: int, rs: int, rt: int) -> int:
    """
    ACT Rd, Rs, Rt - Q1.15 bias-add + activation.

    Note: The activation function is currently encoded in instruction[9:8],
    which overlaps with the Rd field (instruction[11:8]). In practice, choose
    `rd` such that its low 2 bits select the desired activation:
      00=none, 01=ReLU, 10=LeakyReLU, 11=ClippedReLU
    """
    return (0xB << 12) | (rd << 8) | (rs << 4) | rt


def asm_cmp(rd: int, rs: int) -> int:
    """CMP Rd, Rs - Compare and set NZP flags."""
    return (0x2 << 12) | (rd << 8) | (rs << 4)


def asm_br(nzp: int, offset: int) -> int:
    """
    BRnzp offset - Branch on condition.
    
    Args:
        nzp: Condition mask (4=n, 2=z, 1=p)
        offset: PC-relative offset (9 bits)
    """
    return (0x1 << 12) | (nzp << 9) | (offset & 0x1FF)


def asm_brn(offset: int) -> int:
    """Branch if negative."""
    return asm_br(0b100, offset)


def asm_brz(offset: int) -> int:
    """Branch if zero."""
    return asm_br(0b010, offset)


def asm_brp(offset: int) -> int:
    """Branch if positive."""
    return asm_br(0b001, offset)


def asm_brnz(offset: int) -> int:
    """Branch if negative or zero."""
    return asm_br(0b110, offset)


def asm_brnp(offset: int) -> int:
    """Branch if negative or positive (not zero)."""
    return asm_br(0b101, offset)


def asm_brzp(offset: int) -> int:
    """Branch if zero or positive."""
    return asm_br(0b011, offset)


def asm_brnzp(offset: int) -> int:
    """Branch unconditionally."""
    return asm_br(0b111, offset)


# Register aliases
R0, R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12 = range(13)
BLOCK_IDX = 13  # %blockIdx
BLOCK_DIM = 14  # %blockDim
THREAD_IDX = 15  # %threadIdx
