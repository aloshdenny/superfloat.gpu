"""
Trace Formatting Utilities for Atreides GPU

Generates human-readable execution traces showing the cycle-by-cycle
state of the GPU during simulation.
"""

# Opcode to mnemonic mapping
OPCODES = {
    0b0000: "NOP",
    0b0001: "BRnzp",
    0b0010: "CMP",
    0b0011: "ADD",
    0b0100: "SUB",
    0b0101: "MUL",
    0b0110: "DIV",
    0b0111: "LDR",
    0b1000: "STR",
    0b1001: "CONST",
    0b1010: "FMA",
    0b1111: "RET"
}

# Core states
CORE_STATES = {
    0: "IDLE",
    1: "FETCH",
    2: "DECODE",
    3: "REQUEST",
    4: "WAIT",
    5: "EXECUTE",
    6: "UPDATE",
    7: "DONE"
}

# Fetcher states
FETCHER_STATES = {
    0: "IDLE",
    1: "FETCHING",
    2: "DONE"
}

# LSU states
LSU_STATES = {
    0: "IDLE",
    1: "REQUEST",
    2: "WAIT",
    3: "DONE"
}


def decode_instruction(instr: int) -> str:
    """
    Decode a 16-bit instruction into human-readable format.
    
    Args:
        instr: 16-bit instruction word
        
    Returns:
        String representation of the instruction
    """
    opcode = (instr >> 12) & 0xF
    rd = (instr >> 8) & 0xF
    rs = (instr >> 4) & 0xF
    rt = instr & 0xF
    imm = instr & 0xFF
    
    mnemonic = OPCODES.get(opcode, f"UNK({opcode:04b})")
    
    if opcode == 0b0000:  # NOP
        return "NOP"
    elif opcode == 0b0001:  # BRnzp
        nzp = (instr >> 9) & 0x7
        offset = instr & 0x1FF
        cond = ""
        if nzp & 0x4: cond += "n"
        if nzp & 0x2: cond += "z"
        if nzp & 0x1: cond += "p"
        return f"BR{cond} {offset}"
    elif opcode == 0b0010:  # CMP
        return f"CMP R{rd}, R{rs}"
    elif opcode in [0b0011, 0b0100, 0b0101, 0b0110]:  # ADD, SUB, MUL, DIV
        return f"{mnemonic} R{rd}, R{rs}, R{rt}"
    elif opcode == 0b0111:  # LDR
        return f"LDR R{rd}, R{rs}"
    elif opcode == 0b1000:  # STR
        return f"STR R{rd}, R{rs}"
    elif opcode == 0b1001:  # CONST
        return f"CONST R{rd}, #{imm}"
    elif opcode == 0b1010:  # FMA
        return f"FMA R{rd}, R{rs}, R{rt}"
    elif opcode == 0b1111:  # RET
        return "RET"
    else:
        return f"{mnemonic} R{rd}, R{rs}, R{rt}"


def format_registers(regs: list, block_idx: int, block_dim: int, thread_idx: int) -> str:
    """
    Format register values for display.
    
    Args:
        regs: List of 13 general-purpose register values
        block_idx: Block index (R13)
        block_dim: Block dimension (R14)
        thread_idx: Thread index (R15)
        
    Returns:
        Formatted string of register values
    """
    parts = []
    for i, val in enumerate(regs[:13]):
        parts.append(f"R{i} = {val}")
    parts.append(f"%blockIdx = {block_idx}")
    parts.append(f"%blockDim = {block_dim}")
    parts.append(f"%threadIdx = {thread_idx}")
    return "Registers: " + ", ".join(parts)


def format_thread_state(
    thread_id: int,
    pc: int,
    instruction: int,
    core_state: int,
    fetcher_state: int,
    lsu_state: int,
    registers: list,
    block_idx: int,
    block_dim: int,
    thread_idx: int,
    rs_val: int,
    rt_val: int,
    alu_out: int,
    fma_out: int = None
) -> str:
    """
    Format the state of a single thread for trace output.
    
    Returns:
        Multi-line string with thread state
    """
    lines = []
    lines.append(f"+-------- Thread {thread_id} --------+")
    lines.append(f"PC: {pc}")
    lines.append(f"Instruction: {decode_instruction(instruction)}")
    lines.append(f"Core State: {CORE_STATES.get(core_state, 'UNKNOWN')}")
    lines.append(f"Fetcher State: {FETCHER_STATES.get(fetcher_state, 'UNKNOWN')}")
    lines.append(f"LSU State: {LSU_STATES.get(lsu_state, 'UNKNOWN')}")
    lines.append(format_registers(registers, block_idx, block_dim, thread_idx))
    lines.append(f"RS = {rs_val}, RT = {rt_val}")
    
    if fma_out is not None:
        lines.append(f"ALU Out: {alu_out}, FMA Out: {fma_out}")
    else:
        lines.append(f"ALU Out: {alu_out}")
    
    return "\n".join(lines)


def format_cycle_header(cycle: int) -> str:
    """Format the cycle header."""
    return f"{'=' * 35} Cycle {cycle} {'=' * 35}"


def format_core_header(core_id: int) -> str:
    """Format the core header."""
    return f"+{'-' * 22} Core {core_id} {'-' * 22}+"


def format_trace(
    cycle: int,
    cores: list
) -> str:
    """
    Format a complete trace for one cycle.
    
    Args:
        cycle: Current cycle number
        cores: List of core data, each containing thread states
        
    Returns:
        Complete formatted trace string
    """
    lines = [format_cycle_header(cycle), ""]
    
    for core_id, core in enumerate(cores):
        lines.append(format_core_header(core_id))
        lines.append("")
        
        for thread in core['threads']:
            lines.append(format_thread_state(**thread))
            lines.append("")
    
    return "\n".join(lines)


def format_memory_dump(memory: dict, start_addr: int = 0, count: int = 32, title: str = "Memory") -> str:
    """
    Format a memory dump for display.
    
    Args:
        memory: Dictionary of address -> value
        start_addr: Starting address
        count: Number of addresses to show
        title: Title for the memory dump
        
    Returns:
        Formatted memory dump string
    """
    lines = [f"=== {title} (addresses {start_addr} to {start_addr + count - 1}) ==="]
    
    for i in range(0, count, 8):
        row = []
        for j in range(8):
            addr = start_addr + i + j
            val = memory.get(addr, 0)
            row.append(f"{val:04X}")
        lines.append(f"  {start_addr + i:3d}: " + " ".join(row))
    
    return "\n".join(lines)

