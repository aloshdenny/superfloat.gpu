"""
FP16 / BF16 arithmetic through the ISA (tb_gpu compiled with NUMBER_FORMAT 1 or 2)

test_fp_fma_act
    32 threads (4 tiles) each run K iterations of
        FMA R11, x, w        R11 = round(x * w + acc)
        ACT R4..R7, x, bias  f(round(x + bias)), f = none / ReLU / leaky / clipped
    on operands mixing ordinary values, signed zeros, infinities, NaN, values
    near overflow and near the smallest normal, and near-cancelling addends.
    Every result is compared bit-exactly with helpers/fp16fmt.py.

test_fp_systolic8_special_values
    The systolic8 kernel of test_openframe_tile.py on operands that include
    signed zeros, infinities, NaN, overflowing products and results below the
    smallest normal, checked against the fp_systolic_pe model.

Both tests are skipped for SF16 (NUMBER_FORMAT 0).
"""

import os
import random
import sys

import cocotb

sys.path.insert(0, os.path.dirname(__file__))
from helpers.memory import (
    read_memory_range,
    asm_mul, asm_add, asm_const, asm_ldr, asm_str, asm_ret, asm_fma, asm_act,
    asm_cmp, asm_brn,
    R0, R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12,
    BLOCK_IDX, THREAD_IDX,
)
from helpers.number_format import NAMES, number_format, fp_format
from helpers.setup import setup_test, run_kernel
from test_openframe_tile import (
    N, NUM_TILES, BLOCK_STRIDE, A_OFF, B_OFF, C_OFF,
    build_systolic8_program, expected_block,
)

THREADS = N * NUM_TILES
K = 8                     # vectors per thread
IN_WORDS = 4              # x, w, acc, bias
OUT_WORDS = 5             # fma, act none, ReLU, leaky, clipped
OUT_BASE = 2048


def special_values(F):
    W = F.width
    top = 1 << (W - 1)
    max_normal = ((F.emax_field - 1) << F.m) | ((1 << F.m) - 1)
    min_normal = 1 << F.m
    return [0, top, F.inf(0), F.inf(1), F.qnan, F.qnan | 1, top | F.qnan,
            max_normal, top | max_normal, min_normal, top | min_normal,
            min_normal | 1, 1, top | 5,                 # subnormal encodings read as zero
            F.one(), top | F.one(), F.one() + 1, F.one() - 1]


def random_value(rng, F, specials):
    r = rng.random()
    if r < 0.15:
        return rng.choice(specials)
    if r < 0.30:
        return rng.getrandbits(F.width)
    sign = rng.choice((1.0, -1.0))
    if r < 0.40:                                          # near the smallest normal
        return F.from_float(sign * rng.uniform(1.0, 4.0) * 2.0 ** (F.emin - rng.randint(0, 2)))
    if r < 0.50:                                          # near overflow
        return F.from_float(sign * rng.uniform(1.0, 2.0) * 2.0 ** (F.emax - rng.randint(0, 3)))
    return F.from_float(sign * rng.uniform(1.0, 2.0) * 2.0 ** rng.randint(-8, 8))


def make_vectors(rng, F):
    specials = special_values(F)
    vecs = []
    for i in range(THREADS * K):
        x = random_value(rng, F, specials)
        w = random_value(rng, F, specials)
        acc = random_value(rng, F, specials)
        bias = random_value(rng, F, specials)
        if i % 4 == 1:                                    # acc ~ -(x * w): cancellation
            p = F.fma(x, w, 0)
            acc = p ^ (1 << (F.width - 1))
            if rng.random() < 0.5 and 0 < (acc >> F.m) & F.emax_field < F.emax_field:
                acc += rng.choice((-1, 1))
        if i % 4 == 2:                                    # bias ~ -x
            bias = x ^ (1 << (F.width - 1))
            if rng.random() < 0.5 and 0 < (bias >> F.m) & F.emax_field < F.emax_field:
                bias += rng.choice((-1, 1))
        vecs.append((x, w, acc, bias))
    return vecs


def build_fma_act_program() -> list:
    """
    R1 = 1, R0 = K, R9 = k
    R3  = &in[g][0]      g = blockIdx*8 + tid, IN_WORDS*K words per thread
    R12 = &out[g][0]     OUT_BASE + g*OUT_WORDS*K
    x R8, w R10, acc R11, bias R2; ACT writes R4..R7 (Rd[1:0] = function)
    """
    p = [asm_const(R1, 1), asm_const(R0, K), asm_const(R9, 0),
         asm_const(R4, N), asm_mul(R3, BLOCK_IDX, R4), asm_add(R3, R3, THREAD_IDX),   # g
         asm_const(R4, OUT_WORDS * K), asm_mul(R12, R3, R4),
         asm_const(R4, 64), asm_const(R5, OUT_BASE // 64), asm_mul(R4, R4, R5),
         asm_add(R12, R12, R4),
         asm_const(R4, IN_WORDS * K), asm_mul(R3, R3, R4)]
    loop = len(p)
    p += [asm_ldr(R8, R3), asm_add(R3, R3, R1),
          asm_ldr(R10, R3), asm_add(R3, R3, R1),
          asm_ldr(R11, R3), asm_add(R3, R3, R1),
          asm_ldr(R2, R3), asm_add(R3, R3, R1),
          asm_fma(R11, R8, R10),
          asm_act(R4, R8, R2), asm_act(R5, R8, R2), asm_act(R6, R8, R2), asm_act(R7, R8, R2)]
    for r in (R11, R4, R5, R6, R7):
        p += [asm_str(R12, r), asm_add(R12, R12, R1)]
    p += [asm_add(R9, R9, R1), asm_cmp(R9, R0)]
    p.append(asm_brn(loop - (len(p) + 1)))
    p.append(asm_ret())
    return p


@cocotb.test()
async def test_fp_fma_act(dut):
    fmt_id = number_format(dut)
    F = fp_format(fmt_id)
    if F is None:
        dut._log.info("SF16 build: FP test skipped")
        return
    dut._log.info(f"number format: {NAMES[fmt_id]}")
    vecs = make_vectors(random.Random(0xF16 + fmt_id), F)
    data = [0] * (THREADS * K * IN_WORDS)
    for i, v in enumerate(vecs):
        data[i * IN_WORDS:(i + 1) * IN_WORDS] = v

    program = build_fma_act_program()
    logger = await setup_test(dut, f"fp_fma_act_{NAMES[fmt_id]}", program, data,
                              thread_count=THREADS, verbose=False)
    cycles = await run_kernel(dut, logger, max_cycles=400000, trace_interval=0)
    assert int(dut.done.value) == 1, f"kernel did not finish in {cycles} cycles"
    got = read_memory_range(dut, OUT_BASE, THREADS * K * OUT_WORDS)
    logger.close()

    names = ("fma", "act", "relu", "leaky", "clip")
    bad = []
    for i, (x, w, acc, bias) in enumerate(vecs):
        want = [F.fma(x, w, acc)] + [F.act(x, bias, f) for f in range(4)]
        for j in range(OUT_WORDS):
            g = got[i * OUT_WORDS + j]
            if g != want[j]:
                bad.append(f"{names[j]}(x={x:04X} w={w:04X} acc={acc:04X} bias={bias:04X}) "
                           f"got {g:04X} want {want[j]:04X}")
    dut._log.info(f"fp fma/act: {len(vecs)} vectors x {OUT_WORDS} results, "
                  f"{len(bad)} mismatches, {cycles} cycles")
    assert not bad, f"{len(bad)} mismatches, first: " + "; ".join(bad[:6])


@cocotb.test()
async def test_fp_systolic8_special_values(dut):
    fmt_id = number_format(dut)
    F = fp_format(fmt_id)
    if F is None:
        dut._log.info("SF16 build: FP test skipped")
        return
    rng = random.Random(0x5EC + fmt_id)
    specials = special_values(F)
    data = [0] * (BLOCK_STRIDE * NUM_TILES)
    expected = {}
    for b in range(NUM_TILES):
        A = [[random_value(rng, F, specials) for _ in range(N)] for _ in range(N)]
        B = [[random_value(rng, F, specials) for _ in range(N)] for _ in range(N)]
        base = b * BLOCK_STRIDE
        for i in range(N):
            for k in range(N):
                data[base + A_OFF + i * N + k] = A[i][k]
                data[base + B_OFF + i * N + k] = B[i][k]
        expected[b] = expected_block(A, B, F)

    program = build_systolic8_program()
    logger = await setup_test(dut, f"fp_systolic8_special_{NAMES[fmt_id]}", program, data,
                              thread_count=THREADS, verbose=False)
    cycles = await run_kernel(dut, logger, max_cycles=40000, trace_interval=0)
    assert int(dut.done.value) == 1, f"kernel did not finish in {cycles} cycles"
    logger.close()

    bad = []
    kinds = {"nan": 0, "inf": 0, "zero": 0, "num": 0}
    for b in range(NUM_TILES):
        got = read_memory_range(dut, b * BLOCK_STRIDE + C_OFF, N * N)
        for c in range(N * N):
            kinds[F.decode(expected[b][c])[0]] += 1
            if got[c] != expected[b][c]:
                bad.append((b, c, got[c], expected[b][c]))
    dut._log.info(f"fp systolic specials: result kinds {kinds}, {len(bad)} mismatches")
    assert not bad, "mismatches (block, cell, got, want): " + ", ".join(
        f"({b}, {c}, {g:04X}, {w:04X})" for b, c, g, w in bad[:6])
