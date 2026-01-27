"""
Decoder Unit Tests for Atreides GPU

Tests the instruction decoder for all ISA opcodes:
- NOP: No operation
- BRnzp: Branch on condition
- CMP: Compare (sets NZP flags)
- ADD, SUB, MUL, DIV: Integer arithmetic
- LDR: Load from memory
- STR: Store to memory
- CONST: Load immediate
- FMA: Q1.15 fused multiply-add
- ACT: Activation function
- RET: Return (end thread)
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from helpers.logger import GPULogger


# Core states
STATE_IDLE = 0b000
STATE_FETCH = 0b001
STATE_DECODE = 0b010
STATE_REQUEST = 0b011
STATE_WAIT = 0b100
STATE_EXECUTE = 0b101
STATE_UPDATE = 0b110

# Opcodes
OP_NOP = 0x0
OP_BR = 0x1
OP_CMP = 0x2
OP_ADD = 0x3
OP_SUB = 0x4
OP_MUL = 0x5
OP_DIV = 0x6
OP_LDR = 0x7
OP_STR = 0x8
OP_CONST = 0x9
OP_FMA = 0xA
OP_ACT = 0xB
OP_RET = 0xF

# Register input mux values
REG_MUX_ALU = 0b000
REG_MUX_MEM = 0b001
REG_MUX_CONST = 0b010
REG_MUX_FMA = 0b011
REG_MUX_ACT = 0b100

# ALU arithmetic mux
ALU_ADD = 0b00
ALU_SUB = 0b01
ALU_MUL = 0b10
ALU_DIV = 0b11


def encode_instruction(opcode: int, rd: int = 0, rs: int = 0, rt: int = 0, 
                       imm: int = 0, nzp: int = 0) -> int:
    """Encode an instruction."""
    if opcode == OP_CONST:
        # CONST: opcode[15:12] | rd[11:8] | immediate[7:0]
        return (opcode << 12) | (rd << 8) | (imm & 0xFF)
    elif opcode == OP_BR:
        # BR: opcode[15:12] | nzp[11:9] | offset[8:0]
        return (opcode << 12) | (nzp << 9) | (imm & 0x1FF)
    else:
        # Standard: opcode[15:12] | rd[11:8] | rs[7:4] | rt[3:0]
        return (opcode << 12) | (rd << 8) | (rs << 4) | rt


async def setup_decoder_test(dut, test_name: str, clock_period_ns: int = 10) -> GPULogger:
    """Set up decoder test environment."""
    logger = GPULogger(test_name, log_dir="test/results")
    logger.set_verbose(True)
    
    logger.log_section(f"Decoder Unit Test: {test_name}")
    
    # Start clock
    clock = Clock(dut.clk, clock_period_ns, units="ns")
    cocotb.start_soon(clock.start())
    
    # Initialize signals
    dut.reset.value = 1
    dut.core_state.value = STATE_IDLE
    dut.instruction.value = 0
    
    # Wait for reset
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await ClockCycles(dut.clk, 2)
    
    return logger


async def decode_instruction(dut, instruction: int) -> dict:
    """
    Decode an instruction and return all output signals.
    
    Args:
        dut: Device under test
        instruction: 16-bit instruction
        
    Returns:
        Dictionary of decoded signals
    """
    dut.instruction.value = instruction
    dut.core_state.value = STATE_DECODE
    
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)  # Wait for decode to complete
    
    result = {
        'rd': int(dut.decoded_rd_address.value),
        'rs': int(dut.decoded_rs_address.value),
        'rt': int(dut.decoded_rt_address.value),
        'nzp': int(dut.decoded_nzp.value),
        'immediate': int(dut.decoded_immediate.value),
        'reg_write_enable': int(dut.decoded_reg_write_enable.value),
        'mem_read_enable': int(dut.decoded_mem_read_enable.value),
        'mem_write_enable': int(dut.decoded_mem_write_enable.value),
        'nzp_write_enable': int(dut.decoded_nzp_write_enable.value),
        'reg_input_mux': int(dut.decoded_reg_input_mux.value),
        'alu_arithmetic_mux': int(dut.decoded_alu_arithmetic_mux.value),
        'alu_output_mux': int(dut.decoded_alu_output_mux.value),
        'pc_mux': int(dut.decoded_pc_mux.value),
        'fma_enable': int(dut.decoded_fma_enable.value),
        'act_enable': int(dut.decoded_act_enable.value),
        'act_func': int(dut.decoded_act_func.value),
        'ret': int(dut.decoded_ret.value),
    }
    
    dut.core_state.value = STATE_IDLE
    return result


def check_signals(decoded: dict, expected: dict, logger) -> bool:
    """Check if decoded signals match expected values."""
    passed = True
    for key, exp_val in expected.items():
        if key in decoded and decoded[key] != exp_val:
            logger.log_message(f"    MISMATCH: {key} = {decoded[key]}, expected {exp_val}")
            passed = False
    return passed


@cocotb.test()
async def test_decoder_nop(dut):
    """Test NOP instruction decoding."""
    logger = await setup_decoder_test(dut, "decoder_nop")
    
    instr = encode_instruction(OP_NOP)
    logger.log_message(f"  NOP: 0x{instr:04X}")
    
    decoded = await decode_instruction(dut, instr)
    
    # NOP should not enable anything
    expected = {
        'reg_write_enable': 0,
        'mem_read_enable': 0,
        'mem_write_enable': 0,
        'fma_enable': 0,
        'act_enable': 0,
        'ret': 0,
    }
    
    passed = check_signals(decoded, expected, logger)
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Decoder NOP test failed"


@cocotb.test()
async def test_decoder_arithmetic(dut):
    """Test arithmetic instruction decoding (ADD, SUB, MUL, DIV)."""
    logger = await setup_decoder_test(dut, "decoder_arithmetic")
    
    test_cases = [
        (OP_ADD, ALU_ADD, "ADD"),
        (OP_SUB, ALU_SUB, "SUB"),
        (OP_MUL, ALU_MUL, "MUL"),
        (OP_DIV, ALU_DIV, "DIV"),
    ]
    
    passed = True
    
    for opcode, expected_alu_mux, name in test_cases:
        instr = encode_instruction(opcode, rd=5, rs=3, rt=2)
        logger.log_message(f"  {name} R5, R3, R2: 0x{instr:04X}")
        
        decoded = await decode_instruction(dut, instr)
        
        expected = {
            'rd': 5,
            'rs': 3,
            'rt': 2,
            'reg_write_enable': 1,
            'reg_input_mux': REG_MUX_ALU,
            'alu_arithmetic_mux': expected_alu_mux,
            'alu_output_mux': 0,
            'mem_read_enable': 0,
            'mem_write_enable': 0,
        }
        
        if not check_signals(decoded, expected, logger):
            passed = False
        else:
            logger.log_message(f"    PASS: alu_mux={decoded['alu_arithmetic_mux']}")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Decoder arithmetic test failed"


@cocotb.test()
async def test_decoder_cmp(dut):
    """Test CMP instruction decoding."""
    logger = await setup_decoder_test(dut, "decoder_cmp")
    
    instr = encode_instruction(OP_CMP, rd=5, rs=3)
    logger.log_message(f"  CMP R5, R3: 0x{instr:04X}")
    
    decoded = await decode_instruction(dut, instr)
    
    expected = {
        'rd': 5,
        # CMP compares (Rd vs Rs). Decoder remaps sources so ALU sees rs=Rd, rt=Rs.
        'rs': 5,
        'rt': 3,
        'alu_output_mux': 1,  # Compare mode
        'nzp_write_enable': 1,
        'reg_write_enable': 0,
    }
    
    passed = check_signals(decoded, expected, logger)
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Decoder CMP test failed"


@cocotb.test()
async def test_decoder_branch(dut):
    """Test BRnzp instruction decoding."""
    logger = await setup_decoder_test(dut, "decoder_branch")
    
    test_cases = [
        (0b100, "BRn"),   # Branch if negative
        (0b010, "BRz"),   # Branch if zero
        (0b001, "BRp"),   # Branch if positive
        (0b111, "BRnzp"), # Unconditional branch
    ]
    
    passed = True
    
    for nzp, name in test_cases:
        offset = 10
        instr = encode_instruction(OP_BR, nzp=nzp, imm=offset)
        logger.log_message(f"  {name} +{offset}: 0x{instr:04X}")
        
        decoded = await decode_instruction(dut, instr)
        
        expected = {
            'nzp': nzp,
            'pc_mux': 1,  # Select branch target
            'reg_write_enable': 0,
        }
        
        if not check_signals(decoded, expected, logger):
            passed = False
        else:
            logger.log_message(f"    PASS: nzp={decoded['nzp']}, pc_mux={decoded['pc_mux']}")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Decoder branch test failed"


@cocotb.test()
async def test_decoder_ldr(dut):
    """Test LDR instruction decoding."""
    logger = await setup_decoder_test(dut, "decoder_ldr")
    
    instr = encode_instruction(OP_LDR, rd=5, rs=3)
    logger.log_message(f"  LDR R5, R3: 0x{instr:04X}")
    
    decoded = await decode_instruction(dut, instr)
    
    expected = {
        'rd': 5,
        'rs': 3,
        'reg_write_enable': 1,
        'reg_input_mux': REG_MUX_MEM,
        'mem_read_enable': 1,
        'mem_write_enable': 0,
    }
    
    passed = check_signals(decoded, expected, logger)
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Decoder LDR test failed"


@cocotb.test()
async def test_decoder_str(dut):
    """Test STR instruction decoding."""
    logger = await setup_decoder_test(dut, "decoder_str")
    
    instr = encode_instruction(OP_STR, rd=5, rs=3)
    logger.log_message(f"  STR R5, R3: 0x{instr:04X}")
    
    decoded = await decode_instruction(dut, instr)
    
    expected = {
        'rd': 5,
        # STR stores Rs to memory[Rd]. Decoder remaps sources so LSU sees rs=Rd, rt=Rs.
        'rs': 5,
        'rt': 3,
        'reg_write_enable': 0,
        'mem_read_enable': 0,
        'mem_write_enable': 1,
    }
    
    passed = check_signals(decoded, expected, logger)
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Decoder STR test failed"


@cocotb.test()
async def test_decoder_const(dut):
    """Test CONST instruction decoding."""
    logger = await setup_decoder_test(dut, "decoder_const")
    
    test_immediates = [0, 1, 127, 255]
    passed = True
    
    for imm in test_immediates:
        instr = encode_instruction(OP_CONST, rd=5, imm=imm)
        logger.log_message(f"  CONST R5, #{imm}: 0x{instr:04X}")
        
        decoded = await decode_instruction(dut, instr)
        
        expected = {
            'rd': 5,
            'immediate': imm,
            'reg_write_enable': 1,
            'reg_input_mux': REG_MUX_CONST,
        }
        
        if not check_signals(decoded, expected, logger):
            passed = False
        else:
            logger.log_message(f"    PASS: immediate={decoded['immediate']}")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Decoder CONST test failed"


@cocotb.test()
async def test_decoder_fma(dut):
    """Test FMA instruction decoding."""
    logger = await setup_decoder_test(dut, "decoder_fma")
    
    instr = encode_instruction(OP_FMA, rd=5, rs=3, rt=2)
    logger.log_message(f"  FMA R5, R3, R2: 0x{instr:04X}")
    
    decoded = await decode_instruction(dut, instr)
    
    expected = {
        'rd': 5,
        'rs': 3,
        'rt': 2,
        'reg_write_enable': 1,
        'reg_input_mux': REG_MUX_FMA,
        'fma_enable': 1,
    }
    
    passed = check_signals(decoded, expected, logger)
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Decoder FMA test failed"


@cocotb.test()
async def test_decoder_act(dut):
    """Test ACT instruction decoding with different activation functions."""
    logger = await setup_decoder_test(dut, "decoder_act")
    
    # ACT instruction: act_func is encoded in rd[1:0] (instruction[9:8])
    test_funcs = [
        (0b00, "NONE"),
        (0b01, "ReLU"),
        (0b10, "LeakyReLU"),
        (0b11, "ClippedReLU"),
    ]
    
    passed = True
    
    for act_func, name in test_funcs:
        # rd field encodes activation function in bits [1:0]
        rd_with_func = act_func  # Just use act_func as rd to get it in position
        instr = encode_instruction(OP_ACT, rd=rd_with_func, rs=3, rt=2)
        logger.log_message(f"  ACT.{name} R{rd_with_func}, R3, R2: 0x{instr:04X}")
        
        decoded = await decode_instruction(dut, instr)
        
        expected = {
            'rs': 3,
            'rt': 2,
            'reg_write_enable': 1,
            'reg_input_mux': REG_MUX_ACT,
            'act_enable': 1,
            'act_func': act_func,
        }
        
        if not check_signals(decoded, expected, logger):
            passed = False
        else:
            logger.log_message(f"    PASS: act_enable={decoded['act_enable']}, act_func={decoded['act_func']}")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Decoder ACT test failed"


@cocotb.test()
async def test_decoder_ret(dut):
    """Test RET instruction decoding."""
    logger = await setup_decoder_test(dut, "decoder_ret")
    
    instr = encode_instruction(OP_RET)
    logger.log_message(f"  RET: 0x{instr:04X}")
    
    decoded = await decode_instruction(dut, instr)
    
    expected = {
        'ret': 1,
        'reg_write_enable': 0,
        'mem_read_enable': 0,
        'mem_write_enable': 0,
    }
    
    passed = check_signals(decoded, expected, logger)
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Decoder RET test failed"


@cocotb.test()
async def test_decoder_register_addresses(dut):
    """Test all register address combinations."""
    logger = await setup_decoder_test(dut, "decoder_registers")
    
    passed = True
    
    # Test various register combinations
    for rd in [0, 5, 12, 15]:
        for rs in [0, 3, 10, 15]:
            for rt in [0, 2, 7, 15]:
                instr = encode_instruction(OP_ADD, rd=rd, rs=rs, rt=rt)
                decoded = await decode_instruction(dut, instr)
                
                if decoded['rd'] != (rd & 0xF) or decoded['rs'] != (rs & 0xF) or decoded['rt'] != (rt & 0xF):
                    passed = False
                    logger.log_message(f"  MISMATCH: rd={rd}, rs={rs}, rt={rt}")
    
    if passed:
        logger.log_message("  All register address combinations passed")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Decoder register addresses test failed"


@cocotb.test()
async def test_decoder_all_opcodes(dut):
    """Summary test of all opcodes."""
    logger = await setup_decoder_test(dut, "decoder_all_opcodes")
    
    opcodes = [
        (OP_NOP, "NOP", {}),
        (OP_BR, "BR", {'pc_mux': 1}),
        (OP_CMP, "CMP", {'alu_output_mux': 1, 'nzp_write_enable': 1}),
        (OP_ADD, "ADD", {'reg_write_enable': 1, 'reg_input_mux': REG_MUX_ALU}),
        (OP_SUB, "SUB", {'reg_write_enable': 1, 'reg_input_mux': REG_MUX_ALU}),
        (OP_MUL, "MUL", {'reg_write_enable': 1, 'reg_input_mux': REG_MUX_ALU}),
        (OP_DIV, "DIV", {'reg_write_enable': 1, 'reg_input_mux': REG_MUX_ALU}),
        (OP_LDR, "LDR", {'reg_write_enable': 1, 'mem_read_enable': 1, 'reg_input_mux': REG_MUX_MEM}),
        (OP_STR, "STR", {'mem_write_enable': 1}),
        (OP_CONST, "CONST", {'reg_write_enable': 1, 'reg_input_mux': REG_MUX_CONST}),
        (OP_FMA, "FMA", {'reg_write_enable': 1, 'fma_enable': 1, 'reg_input_mux': REG_MUX_FMA}),
        (OP_ACT, "ACT", {'reg_write_enable': 1, 'act_enable': 1, 'reg_input_mux': REG_MUX_ACT}),
        (OP_RET, "RET", {'ret': 1}),
    ]
    
    passed = True
    
    for opcode, name, expected in opcodes:
        if opcode == OP_CONST:
            instr = encode_instruction(opcode, rd=1, imm=42)
        elif opcode == OP_BR:
            instr = encode_instruction(opcode, nzp=0b111, imm=5)
        else:
            instr = encode_instruction(opcode, rd=1, rs=2, rt=3)
        
        decoded = await decode_instruction(dut, instr)
        
        opcode_passed = check_signals(decoded, expected, logger)
        if not opcode_passed:
            passed = False
            logger.log_message(f"  {name}: FAIL")
        else:
            logger.log_message(f"  {name}: PASS")
    
    logger.log_message(f"\nOverall: {'PASS' if passed else 'FAIL'}")
    logger.close()
    
    assert passed, "Decoder all opcodes test failed"
