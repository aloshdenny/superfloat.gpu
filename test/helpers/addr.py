"""
Address Builder Helpers for Atreides GPU ISA
=============================================

The CONST instruction sign-extends an 8-bit immediate into a 16-bit register,
giving a range of -128..+127 (i.e., non-negative values up to 127).  Large
addresses (>127) require multiple instructions.

build_large_const() uses a binary doubling strategy:

1. Right-shift `val` until the result fits in 0..127 — this gives the *base*.
2. Emit CONST(reg, base).
3. For each shifted-out bit position (MSB-first), double the register with
   ADD(reg, reg, reg).  If that bit was set in `val`, emit CONST(scratch, 1)
   followed by ADD(reg, reg, scratch) to add the single bit back.

Examples
--------
  256  = 64 << 2   →  CONST(64) + ADD + ADD                      (3 instr)
  512  = 64 << 3   →  CONST(64) + ADD + ADD + ADD                (4 instr)
   81  = (40 << 1) | 1  →  CONST(40) + ADD + CONST(1) + ADD      (4 instr)
  162  = 81 << 1   →  CONST(81) + ADD                            (2 instr)
 1024  = 64 << 4   →  CONST(64) + 4×ADD                         (5 instr)
 4096  = 64 << 6   →  CONST(64) + 6×ADD                         (7 instr)
"""

from .memory import asm_const, asm_add, R11


def build_large_const(reg: int, val: int, scratch_reg: int = R11) -> list:
    """
    Emit instructions to load an arbitrary non-negative integer into *reg*.

    Parameters
    ----------
    reg : int
        Destination register (0-12).  Must differ from *scratch_reg*.
    val : int
        Non-negative value to load, 0 ≤ val < 65536.
    scratch_reg : int
        Scratch register used for +1 additions when an intermediate value
        has a set bit that must be re-added.  Defaults to R11.
        Must differ from *reg*.

    Returns
    -------
    list[int]
        Assembled 16-bit instruction words.

    Raises
    ------
    AssertionError
        If val is out of range or reg == scratch_reg.
    """
    assert 0 <= val < 65536, f"val={val} is out of 16-bit range [0, 65535]"
    assert reg != scratch_reg, (
        f"reg ({reg}) and scratch_reg ({scratch_reg}) must differ"
    )

    # Fast path: value fits directly in an 8-bit sign-extended immediate
    if val <= 127:
        return [asm_const(reg, val)]

    # --- Find shift amount ---
    # Right-shift val until the shifted value ≤ 127
    shift_amount = 0
    base = val
    while base > 127:
        shift_amount += 1
        base = val >> shift_amount

    # base ≤ 127, base << shift_amount ≤ val (we recover the rest via +1 additions)
    instrs = [asm_const(reg, base)]

    # --- Reconstruct val by doubling and adding set bits ---
    # Process bit positions from (shift_amount-1) down to 0
    for bit_pos in range(shift_amount - 1, -1, -1):
        # Double: reg = reg * 2
        instrs.append(asm_add(reg, reg, reg))
        # If this bit position is set in val, add 1
        if (val >> bit_pos) & 1:
            instrs.append(asm_const(scratch_reg, 1))
            instrs.append(asm_add(reg, reg, scratch_reg))

    return instrs


def large_const_cost(val: int) -> int:
    """
    Return the number of instructions build_large_const would emit for *val*.
    Useful for instruction-budget calculations.
    """
    if val <= 127:
        return 1
    shift_amount = 0
    base = val
    while base > 127:
        shift_amount += 1
        base = val >> shift_amount
    cost = 1 + shift_amount  # CONST + one ADD per doubling
    for bit_pos in range(shift_amount - 1, -1, -1):
        if (val >> bit_pos) & 1:
            cost += 2  # CONST(1) + ADD for each set bit
    return cost
