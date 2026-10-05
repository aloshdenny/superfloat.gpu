"""Check the emulation kernels against slow per-MAC references
(test/helpers/fp16fmt.py for FP16/BF16; plain integer loops for SF16)."""
import os
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "..", "test", "helpers"))
import mxu_emu as E                                   # noqa: E402
from fp16fmt import FP16, BF16                        # noqa: E402

rng = np.random.default_rng(1)


def ref_int(A, B, shift, lo, hi):
    T, K = A.shape
    N = B.shape[1]
    out = np.zeros((T, N), np.int64)
    for t in range(T):
        for n in range(N):
            acc = 0
            for k in range(K):
                p = int(A[t, k]) * int(B[k, n])
                q = abs(p) >> shift
                acc = min(max(acc + (q if p >= 0 else -q), lo), hi)
            out[t, n] = acc
    return out


def check_sf16():
    for scale in (0.05, 1.0):           # 1.0 forces saturation
        A = E.sf16_ints(rng.uniform(-1, 1, (5, 300)) * scale, 0)
        B = E.sf16_ints(rng.uniform(-1, 1, (300, 7)), 0)
        a, c = E.k_fix(A, B, 15, 16)
        assert (a == ref_int(A, B, 15, -32768, 32767)).all(), "sat16"
        a, _ = E.k_fix(A, B, 11, 24)
        assert (a == ref_int(A, B, 11, -2 ** 23, 2 ** 23 - 1)).all(), "sf24"
        a, _ = E.k_fix(A, B, 7, 32)
        assert (a == ref_int(A, B, 7, -2 ** 31, 2 ** 31 - 1)).all(), "sf32"
        print(f"sf16 kernels exact (scale {scale}, sat16 clips {int(c.sum())})")


def check_fp(fmt, F):
    m, emin, emax = E.FMTS[fmt]
    for spread in (1.0, 40.0):          # 40: wide exponents, FTZ and overflow
        A = E.fp_round(rng.standard_normal((4, 200)) * np.exp(rng.uniform(-spread, spread, (4, 200)) / 4), fmt)
        B = E.fp_round(rng.standard_normal((200, 6)) * np.exp(rng.uniform(-spread, spread, (200, 6)) / 4), fmt)
        got = E.k_fpnat(A, B, m, emin, emax)
        bits = lambda x: F.from_float(float(x))
        bad = 0
        for t in range(A.shape[0]):
            for n in range(B.shape[1]):
                acc = F.zero(0)
                for k in range(A.shape[1]):
                    if A[t, k] == 0.0:
                        continue
                    acc = F.fma(bits(A[t, k]), bits(B[k, n]), acc)
                r = F.to_float(acc)
                g = got[t, n]
                same = (np.isnan(r) and np.isnan(g)) or (r == g and np.signbit(r) == np.signbit(g))
                bad += not same
        print(f"{fmt} fused kernel: {bad} mismatches of {A.shape[0] * B.shape[1]} (spread {spread})")
        assert bad == 0
    x = rng.standard_normal(100000) * np.exp(rng.uniform(-60, 60, 100000))
    y = E.fp_round(x, fmt)
    ref = np.array([F.to_float(F.from_float(float(v))) for v in x])
    ok = ((y == ref) | (np.isnan(y) & np.isnan(ref))).mean()
    print(f"{fmt} fp_round agrees with the reference on {ok:.6f} of 100k values")


check_sf16()
check_fp("fp16", FP16)
check_fp("bf16", BF16)

T, K, N = 1024, 768, 3072
A = rng.uniform(-1, 1, (T, K)).astype(np.float32) * 0.1
B = rng.uniform(-1, 1, (K, N)).astype(np.float32) * 0.1
for name in E.CASES:
    c = E.Case(name)
    c.matmul(A[:8], B[:, :8])
    t = time.perf_counter()
    c.matmul(A, B)
    dt = time.perf_counter() - t
    print(f"{name:12s} {T}x{K}x{N}: {dt:6.2f} s  {T * K * N / dt / 1e9:6.2f} GMAC/s")


# Truncated kernels against the RTL checker's reference (v3/pe/check_block.py).
sys.path.insert(0, os.path.join(HERE, "..", "pe"))
from check_block import tmul                           # noqa: E402
A = E.sf16_ints(rng.uniform(-1, 1, (5, 300)) * 0.3, 0)
B = E.sf16_ints(rng.uniform(-1, 1, (300, 7)), 0)
for (drop, width, tk, comp) in [(11, 24, 9, 1024), (7, 28, 6, 80), (7, 32, 6, 80)]:
    got, _ = E.k_fix_t(A, B, drop, width, tk, comp)
    ref = np.zeros_like(got)
    for t in range(A.shape[0]):
        for n in range(B.shape[1]):
            acc = 0
            for k in range(A.shape[1]):
                a, b = int(A[t, k]), int(B[k, n])
                q = (tmul(abs(a), abs(b), tk, comp) if a else 0) >> drop
                acc = min(max(acc + (-q if (a < 0) != (b < 0) else q), -(1 << (width - 1))), (1 << (width - 1)) - 1)
            ref[t, n] = acc
    print(f"k_fix_t K={tk}: {'exact' if (got == ref).all() else 'MISMATCH'}")
    assert (got == ref).all()
x = E.fp_round(rng.standard_normal((4, 200)), "fp16")
y = E.fp_round(rng.standard_normal((200, 6)) * 0.05, "fp16")
MA, EA = E.sig_exp(x, 10)
MB, EB = E.sig_exp(y, 10)
got = E.k_fpnat_t(MA, EA, MB, EB, 4, 12, 15, -126, 127)
from check_block import Fmt, fma_mixed                   # noqa: E402
fi, fa = Fmt("in", 5, 10), Fmt("acc", 8, 15)
bad = 0
for t in range(x.shape[0]):
    for n in range(y.shape[1]):
        acc = 0
        for k in range(x.shape[1]):
            acc = fma_mixed(fi, fa, fi.from_float(float(x[t, k])), fi.from_float(float(y[k, n])), acc, 4, 12)
        bad += fa.to_float(acc) != got[t, n]
print(f"k_fpnat_t: {bad} mismatches of {x.shape[0] * y.shape[1]}")
assert bad == 0
