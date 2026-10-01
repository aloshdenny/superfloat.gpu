"""
Address Builder Helpers for Atreides GPU ISA
=============================================

CONST sign-extends an 8-bit immediate into a 16-bit register (-128..+127).
CONSTH writes a register's high byte and keeps its low byte, so any 16-bit
value loads in two instructions: CONST with the low byte (its sign extension
is overwritten), then CONSTH with the high byte.

Examples
--------
    100  ->  CONST(100)                         (1 instr)
    256  ->  CONST(0x00) + CONSTH(0x01)         (2 instr)
  40000  ->  CONST(0x40) + CONSTH(0x9C)         (2 instr)
"""

from .memory import asm_const, asm_consth, R11


def build_large_const(reg: int, val: int, scratch_reg: int = R11) -> list:
    """
    Emit instructions to load an arbitrary non-negative integer into *reg*.

    Values up to 127 take one CONST. Larger ones take CONST (low byte,
    sign-extended) and CONSTH (high byte). *scratch_reg* is no longer used and
    is kept so existing callers do not change.

    Parameters
    ----------
    reg : int
        Destination register (0-12).
    val : int
        Non-negative value to load, 0 <= val < 65536.

    Returns
    -------
    list[int]
        Assembled 16-bit instruction words.
    """
    assert 0 <= val < 65536, f"val={val} is out of 16-bit range [0, 65535]"
    if val <= 127:
        return [asm_const(reg, val)]
    return [asm_const(reg, val & 0xFF), asm_consth(reg, val >> 8)]
