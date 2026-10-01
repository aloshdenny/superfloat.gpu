"""
OpenFrame core-tile tests (4 tiles x 8 threads x one 8x8 systolic array)

test_systolic8_all_tiles
    Launches 32 threads = 4 blocks, one per tile. Every block runs the same
    kernel on its own A/B pair through the ISA: SYS clear, eight SYS load
    (weight rows 7..0), eight SYS compute (activation columns k = 0..7), one
    flush compute, then 64 SYS reads stored back to memory. The result is
    checked bit-exactly against a model of systolic_pe (SF16) or
    fp_systolic_pe (FP16/BF16, helpers/fp16fmt.py), following the
    NUMBER_FORMAT the testbench was compiled with.

    Array semantics at the ISA level (weight-stationary):
      PE(i,j) holds B[i][j]; thread i streams row i of A.
      SF16:      C[i][j] = sum_k trunc(A[i][k] * B[i][j])   (16-bit saturating)
      FP16/BF16: C[i][j] = fma(A[i][k], B[i][j], C[i][j]) per k, from +0
    Column 0 accumulates the operand of the current compute; columns >= 1
    accumulate the previous one after it has drained across the row, so one
    trailing compute with R0 = 0 lines every column up.

test_dispatch_many_blocks
    Launches 100 threads = 13 blocks (the last has 4 threads) on the four
    tiles, so tiles finish and take new blocks, several in the same cycle.
    Every thread stores blockIdx*8 + tid + 1 at OUT + blockIdx*8 + tid; the
    four disabled threads of the last block must store nothing.

test_scratchpad_private_per_tile
    All four tiles write the same scratchpad addresses (0xFFC0 + tid) at the
    same time with different values, read their own and a neighbour's slot
    back, and store both to external memory. Each tile must see only its own
    values, and external memory at 0xFFC0.. must stay untouched.

test_sys_back_to_back
    SYS load.b, two SYS computes back to back and a SYS read straight after,
    so the read must wait for the second compute to reach the accumulators
    (and, in FP16/BF16, the computes meet the PE's three-cycle accumulator
    loop at its shortest). R0 is an activation whose low six bits also name
    cell (tid, tid). Checked against the PE models, all four tiles.
"""

import os
import random
import sys

import cocotb

sys.path.insert(0, os.path.dirname(__file__))
from helpers.q115 import float_to_q115, q115_to_float
from helpers.number_format import NAMES, number_format, fp_format
from helpers.memory import (
    read_memory_range,
    asm_mul, asm_add, asm_sub, asm_div, asm_const, asm_ldr, asm_str, asm_ret,
    asm_sh, asm_consth, asm_cmp, asm_brn,
    R0, R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11,
    BLOCK_IDX, THREAD_IDX,
)
from helpers.setup import setup_test, run_kernel

N = 8                 # array edge = threads per block
NUM_TILES = 4
BLOCK_STRIDE = 256    # data words per block
A_OFF, B_OFF, C_OFF = 0, 64, 128

SCRATCH_BASE = 0xFFC0
SCRATCH_OUT = 1024    # external results for the scratchpad test


def sys_op(op: int, rd: int = 0) -> int:
    """SYS op (00 clear, 01 load, 10 compute, 11 read into rd); array index 0."""
    return (0xC << 12) | (rd << 8) | (op << 6)


# ---------------------------------------------------------------------------
# Bit-exact model of systolic_pe (sign-magnitude in, 16-bit saturating acc)
# ---------------------------------------------------------------------------

def _canon(q: int) -> int:
    q &= 0xFFFF
    return 0 if q == 0x8000 else q


def pe_accumulate(activations: list, weight: int) -> int:
    w = _canon(weight)
    acc = 0
    for a in activations:
        a = _canon(a)
        prod = ((a & 0x7FFF) * (w & 0x7FFF)) >> 15
        s = acc - prod if ((a >> 15) ^ (w >> 15)) else acc + prod
        if s > 32767:
            s = 32767
        elif s <= -32768:
            s = -32767
        acc = s
    return (0x8000 | (-acc)) if acc < 0 else acc


def expected_block(A: list, B: list, fmt=None) -> list:
    """C[i][j] = PE(i,j) after the ISA sequence used by the kernel.

    fmt is the FP16/BF16 model (helpers.fp16fmt), or None for SF16.
    """
    C = []
    for i in range(N):
        for j in range(N):
            if j == 0:
                acts = [A[i][k] for k in range(N)] + [0]
            else:
                acts = [0] + [A[i][k] for k in range(N)]
            C.append(fmt.pe_accumulate(acts, B[i][j]) if fmt else pe_accumulate(acts, B[i][j]))
    return C


def random_operand(rng: random.Random, fmt=None) -> int:
    """SF16: uniform in +-0.3. FP16/BF16: uniform in +-2 (many binades)."""
    if fmt:
        return fmt.from_float(rng.uniform(-2.0, 2.0))
    return float_to_q115(rng.uniform(-0.3, 0.3))


# ---------------------------------------------------------------------------
# Kernels
# ---------------------------------------------------------------------------

def build_systolic8_program() -> list:
    """
    R3  = base = blockIdx * 256
    R5  = &B[0][tid]           (weight column pointer)
    R7  = &A[tid][0]           (activation row pointer)
    R9  = &C[tid][0]           (result row pointer)
    R11 = 1                    (pointer step)
    R10 = tid * 8              (first result cell of this thread)
    R0/R1 = SYS operands (a / b)
    """
    p = []
    p += [asm_const(R2, 16),
          asm_mul(R3, BLOCK_IDX, R2),
          asm_mul(R3, R3, R2)]                     # base = blockIdx * 256
    p += [asm_const(R4, B_OFF),
          asm_add(R5, R3, R4),
          asm_add(R5, R5, THREAD_IDX)]             # &B[0][tid]
    p += [asm_const(R4, N),
          asm_mul(R10, THREAD_IDX, R4),            # tid * 8
          asm_add(R7, R3, R10)]                    # &A[tid][0]
    p += [asm_const(R4, C_OFF // 2),
          asm_add(R9, R3, R4),
          asm_add(R9, R9, R4),
          asm_add(R9, R9, R10)]                    # &C[tid][0]

    p += [asm_const(R0, 0), asm_const(R1, 0), sys_op(0b00)]   # clear with zero operands

    for r in reversed(range(N)):                  # weight rows 7..0
        p += [asm_const(R4, r * N), asm_add(R6, R5, R4), asm_ldr(R1, R6), sys_op(0b01)]

    # Activation columns 0..7. The pointer bump right after each compute puts
    # an address in pipe_rs while the array is still draining, which is what
    # the core's SYS operand hold exists for.
    p += [asm_const(R11, 1), asm_add(R6, R7, R11), asm_sub(R6, R6, R11)]   # R6 = &A[tid][0]
    for _ in range(N):
        p += [asm_ldr(R0, R6), sys_op(0b10), asm_add(R6, R6, R11)]

    p += [asm_const(R0, 0), sys_op(0b10)]         # flush: columns >= 1 take A[:, 7]

    for j in range(N):                            # thread tid reads row tid
        p += [asm_const(R4, j),
              asm_add(R0, R10, R4),               # cell = tid*8 + j
              sys_op(0b11, rd=R8),
              asm_add(R6, R9, R4),
              asm_str(R6, R8)]

    p.append(asm_ret())
    return p


def build_scratchpad_program() -> list:
    """
    Own slot:  scratch[tid]            = blockIdx*16 + tid + 1
    Neighbour: scratch[(tid + 1) % 8]  read back after every thread stored
    Out:       mem[1024 + blockIdx*16 + tid]     = own read-back
               mem[1024 + blockIdx*16 + 8 + tid] = neighbour read-back
    """
    p = []
    p += [asm_const(R2, 0), asm_const(R4, 64), asm_sub(R2, R2, R4)]      # 0xFFC0
    p += [asm_add(R3, R2, THREAD_IDX)]                                   # &scratch[tid]
    p += [asm_const(R4, 16), asm_mul(R5, BLOCK_IDX, R4),
          asm_add(R5, R5, THREAD_IDX), asm_const(R4, 1), asm_add(R5, R5, R4)]
    p += [asm_str(R3, R5)]                                               # scratch[tid] = value

    p += [asm_const(R4, 1), asm_add(R6, THREAD_IDX, R4),                 # n = tid + 1
          asm_const(R4, N), asm_div(R7, R6, R4), asm_mul(R7, R7, R4),
          asm_sub(R6, R6, R7),                                           # n % 8
          asm_add(R6, R2, R6)]                                           # &scratch[n % 8]

    p += [asm_ldr(R8, R3), asm_ldr(R9, R6)]                              # own, neighbour

    p += [asm_const(R4, 32), asm_mul(R7, R4, R4),                       # 1024
          asm_const(R4, 16), asm_mul(R10, BLOCK_IDX, R4),
          asm_add(R7, R7, R10), asm_add(R7, R7, THREAD_IDX)]
    p += [asm_str(R7, R8), asm_const(R4, N), asm_add(R7, R7, R4), asm_str(R7, R9)]
    p.append(asm_ret())
    return p


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_systolic8_all_tiles(dut):
    fmt_id = number_format(dut)
    fmt = fp_format(fmt_id)
    dut._log.info(f"number format: {NAMES[fmt_id]}")
    rng = random.Random(0x8A8)
    data = [0] * (BLOCK_STRIDE * NUM_TILES)
    expected = {}
    for b in range(NUM_TILES):
        A = [[random_operand(rng, fmt) for _ in range(N)] for _ in range(N)]
        B = [[random_operand(rng, fmt) for _ in range(N)] for _ in range(N)]
        base = b * BLOCK_STRIDE
        for i in range(N):
            for k in range(N):
                data[base + A_OFF + i * N + k] = A[i][k]
                data[base + B_OFF + i * N + k] = B[i][k]
        expected[b] = expected_block(A, B, fmt)

    program = build_systolic8_program()
    logger = await setup_test(dut, "systolic8_all_tiles", program, data,
                              thread_count=N * NUM_TILES, verbose=False)
    cycles = await run_kernel(dut, logger, max_cycles=40000, trace_interval=0)
    assert int(dut.done.value) == 1, f"kernel did not finish in {cycles} cycles"

    failures = []
    for b in range(NUM_TILES):
        got = read_memory_range(dut, b * BLOCK_STRIDE + C_OFF, N * N)
        bad = [(c, got[c], expected[b][c]) for c in range(N * N) if got[c] != expected[b][c]]
        logger.log_message(f"tile/block {b}: {N*N - len(bad)}/{N*N} cells match")
        if bad:
            failures.append((b, bad[:4]))
    logger.log_message(f"kernel cycles: {cycles}, program: {len(program)} instructions")
    logger.close()
    dut._log.info(f"systolic8: {cycles} cycles, {len(program)} instructions")
    assert not failures, "mismatches (block, [(cell, got, want)]): " + "; ".join(
        f"{b}: " + ", ".join(f"({c}, {g:04X}, {w:04X})" for c, g, w in bad) for b, bad in failures)


DISPATCH_THREADS = 100
DISPATCH_OUT = 2048


def build_dispatch_program() -> list:
    """mem[DISPATCH_OUT + blockIdx*8 + tid] = blockIdx*8 + tid + 1"""
    return [asm_const(R2, N), asm_mul(R3, BLOCK_IDX, R2), asm_add(R3, R3, THREAD_IDX),
            asm_const(R4, 64), asm_const(R5, DISPATCH_OUT // 64), asm_mul(R4, R4, R5),
            asm_add(R5, R4, R3), asm_const(R6, 1), asm_add(R6, R3, R6),
            asm_str(R5, R6), asm_ret()]


@cocotb.test()
async def test_dispatch_many_blocks(dut):
    program = build_dispatch_program()
    logger = await setup_test(dut, "dispatch_many_blocks", program, [0] * 16,
                              thread_count=DISPATCH_THREADS, verbose=False)
    cycles = await run_kernel(dut, logger, max_cycles=40000, trace_interval=0)
    assert int(dut.done.value) == 1, f"kernel did not finish in {cycles} cycles"
    blocks = (DISPATCH_THREADS + N - 1) // N
    got = read_memory_range(dut, DISPATCH_OUT, blocks * N)
    logger.close()
    want = [g + 1 if g < DISPATCH_THREADS else 0 for g in range(blocks * N)]
    bad = [(g, got[g], want[g]) for g in range(blocks * N) if got[g] != want[g]]
    dut._log.info(f"dispatch: {DISPATCH_THREADS} threads, {blocks} blocks, {cycles} cycles")
    assert not bad, f"{len(bad)} wrong slots, first (slot, got, want): {bad[:6]}"


@cocotb.test()
async def test_scratchpad_private_per_tile(dut):
    program = build_scratchpad_program()
    logger = await setup_test(dut, "scratchpad_private_per_tile", program, [0] * 16,
                              thread_count=N * NUM_TILES, verbose=False)
    cycles = await run_kernel(dut, logger, max_cycles=20000, trace_interval=0)
    assert int(dut.done.value) == 1, f"kernel did not finish in {cycles} cycles"

    failures = []
    for b in range(NUM_TILES):
        out = read_memory_range(dut, SCRATCH_OUT + b * 16, 16)
        want_own = [b * 16 + t + 1 for t in range(N)]
        want_nbr = [b * 16 + (t + 1) % N + 1 for t in range(N)]
        if out[:N] != want_own or out[N:] != want_nbr:
            failures.append((b, out, want_own + want_nbr))
    ext_scratch = read_memory_range(dut, SCRATCH_BASE, 64)
    logger.close()
    assert not failures, f"scratchpad mismatch: {failures}"
    assert all(v == 0 for v in ext_scratch), "scratchpad traffic leaked to external memory"


# ---------------------------------------------------------------------------
# SH and CONSTH (ISA v2)
# ---------------------------------------------------------------------------

SHIFT_OUT = 64


def build_sh_consth_program() -> list:
    """Each thread stores five words at SHIFT_OUT + 8 * tid:
    0x1234 (CONST + CONSTH), 0x1234 >> 8, 0x1234 << 3, 0x7F80 (CONSTH over a
    sign-extended low byte) and 0x1234 << tid."""
    p = [asm_const(R1, 0x34), asm_consth(R1, 0x12),
         asm_const(R2, -8 & 0xFF), asm_sh(R3, R1, R2),
         asm_const(R4, 3), asm_sh(R5, R1, R4),
         asm_const(R6, 0x80), asm_consth(R6, 0x7F),
         asm_sh(R7, R1, THREAD_IDX),
         asm_sh(R8, THREAD_IDX, R4),                     # tid * 8
         asm_const(R9, SHIFT_OUT), asm_add(R9, R9, R8),
         asm_const(R10, 1)]
    for r in (R1, R3, R5, R6, R7):
        p += [asm_str(R9, r), asm_add(R9, R9, R10)]
    return p + [asm_ret()]


@cocotb.test()
async def test_sh_consth(dut):
    logger = await setup_test(dut, "sh_consth", build_sh_consth_program(), [0] * 16,
                              thread_count=N, verbose=False)
    cycles = await run_kernel(dut, logger, max_cycles=20000, trace_interval=0)
    assert int(dut.done.value) == 1, f"kernel did not finish in {cycles} cycles"
    got = read_memory_range(dut, SHIFT_OUT, 8 * N)
    logger.close()
    bad = []
    for t in range(N):
        want = [0x1234, 0x0012, 0x91A0, 0x7F80, (0x1234 << t) & 0xFFFF]
        have = [got[8 * t + k] for k in range(5)]
        if have != want:
            bad.append((t, [hex(h) for h in have], [hex(w) for w in want]))
    assert not bad, f"{len(bad)} threads wrong, first (tid, got, want): {bad[:2]}"


# ---------------------------------------------------------------------------
# SYS instructions back to back
# ---------------------------------------------------------------------------

SYS_OUT = 96          # below 128: CONST sign-extends its immediate
# Operands with the low six bits free: 0.5 (SF16), 1.0 (FP16, BF16); weights 0.25 / 0.5.
B2B_ACT = {0: 0x4000, 1: 0x3C00, 2: 0x3F80}
B2B_WEIGHT = {0: 0x2000, 1: 0x3800, 2: 0x3F00}


def build_sys_b2b_program(fmt_id: int) -> list:
    """Thread tid: R0 = act | tid*9 (cell tid*8 + tid), R1 = weight + tid;
    twice (the second pass runs from the instruction buffer, at full speed):
    clear, load.b, three ADDs while the activation crosses the row, compute,
    compute, read. Stores the read at SYS_OUT + 8 * blockIdx + tid."""
    a, w = B2B_ACT[fmt_id], B2B_WEIGHT[fmt_id]
    p = [asm_const(R5, 9), asm_mul(R4, THREAD_IDX, R5),
         asm_const(R0, a & 0xFF), asm_consth(R0, a >> 8), asm_add(R0, R0, R4),
         asm_const(R1, w & 0xFF), asm_consth(R1, w >> 8), asm_add(R1, R1, THREAD_IDX),
         asm_const(R3, 1), asm_const(R6, 2), asm_const(R7, 0)]
    loop = len(p)
    p += [sys_op(0b00), sys_op(0b01) | (1 << 5),
          asm_add(R2, R2, R2), asm_add(R2, R2, R2), asm_add(R2, R2, R2),
          sys_op(0b10), sys_op(0b10), sys_op(0b11, rd=R8),
          asm_add(R7, R7, R3), asm_cmp(R7, R6)]
    p += [asm_brn(loop - (len(p) + 1))]
    p += [asm_const(R9, SYS_OUT), asm_const(R10, N), asm_mul(R11, BLOCK_IDX, R10),
          asm_add(R9, R9, R11), asm_add(R9, R9, THREAD_IDX), asm_str(R9, R8),
          asm_ret()]
    return p


@cocotb.test()
async def test_sys_back_to_back(dut):
    fmt_id = number_format(dut)
    F = fp_format(fmt_id)
    logger = await setup_test(dut, f"sys_b2b_{NAMES[fmt_id]}", build_sys_b2b_program(fmt_id),
                              [0] * 16, thread_count=N * NUM_TILES, verbose=False)
    cycles = await run_kernel(dut, logger, max_cycles=20000, trace_interval=0)
    assert int(dut.done.value) == 1, f"kernel did not finish in {cycles} cycles"
    got = read_memory_range(dut, SYS_OUT, N * NUM_TILES)
    logger.close()
    bad = []
    for b in range(NUM_TILES):
        for t in range(N):
            a, w = B2B_ACT[fmt_id] + 9 * t, B2B_WEIGHT[fmt_id] + t
            want = F.pe_accumulate([a, a], w) if F else pe_accumulate([a, a], w)
            if got[N * b + t] != want:
                bad.append((b, t, hex(got[N * b + t]), hex(want)))
    dut._log.info(f"sys back to back: {N * NUM_TILES} reads, {len(bad)} wrong, {cycles} cycles")
    assert not bad, f"{len(bad)} reads wrong, first (block, tid, got, want): {bad[:4]}"
