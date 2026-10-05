"""
Bit-level emulation of a v3 matrix unit's matmul, per number format and
accumulator (docs/v3_gt2n.md, study S1).

Every case quantizes both operands to its 16-bit format, accumulates the
products along K in order (k = 0, 1, ...), as a weight-stationary column
and its accumulator rows do, and rounds the result once to the 16-bit format
when it leaves the unit (MXU.POP).

  sf16_sat16   SF16 in, v2 PE: product truncated to Q1.15, 16-bit saturating
               accumulator. No headroom: partial sums past +-1 clip.
  sf16_sat16h  The same, with the activations scaled down until the exact
               result fits (an oracle; static calibration can only do worse).
  sf16_sf24    SF16 in, product truncated to 19 fraction bits, Q5.19
               saturating 24-bit accumulator, rounded to SF16 at the pop.
  sf16_sf32    SF16 in, product truncated to 23 fraction bits, Q9.23
               saturating 32-bit accumulator, rounded to SF16 at the pop.
  fp16_nat     FP16 in, v2 PE: fused round(a*b + acc) to FP16 at every step.
  fp16_fp24    FP16 in, fused round(a*b + acc) to a 24-bit float (1/8/15),
               rounded to FP16 at the pop.
  fp16_fp32    FP16 in, FP32 accumulator, rounded to FP16 at the pop.
  bf16_nat, bf16_fp24, bf16_fp32   The same three for BF16.

SF16 tensors carry one power-of-two scale each, chosen so the largest
magnitude fits (inputs and outputs; negative exponents allowed). FP16 and
BF16 round to nearest even, flush subnormals to signed zero (tininess before
rounding) and overflow to infinity, as src/fp_arith.sv does.

The FP32-accumulator cases use a float32 BLAS matmul of the quantized
operands: products are exact in FP32, and the order of the FP32 additions
is BLAS's, not the column's. The fused cases (native and FP24) add in
float64 before rounding to the accumulator's format, which is exact except where an exponent gap
over 31 bits makes the float64 sum inexact and that rounding lands on a
16-bit tie; we take that to be negligible.
"""
import math

import numpy as np
from numba import njit, prange

CASES = ("sf16_sat16", "sf16_sat16h", "sf16_sf24", "sf16_sf32",
         "fp16_nat", "fp16_fp24", "fp16_fp32", "bf16_nat", "bf16_fp24", "bf16_fp32")
# SF16 accumulators: (fraction bits kept per product, total width)
FIX = {"sf16_sat16": (15, 16), "sf16_sat16h": (15, 16),
       "sf16_sf24": (19, 24), "sf16_sf32": (23, 32)}


# ------------------------------------------------------------------ SF16

def scale_exp(m: float) -> int:
    """The power of two e with m / 2**e < 1 (any sign of e)."""
    if m <= 0.0 or not math.isfinite(m):
        return 0
    return int(math.floor(math.log2(m))) + 1


def sf16_ints(a: np.ndarray, e: int) -> np.ndarray:
    """Signed Q1.15 integers (sign-magnitude rounding, |q| <= 32767)."""
    x = np.asarray(a, dtype=np.float64) * (2.0 ** (15 - e))
    q = np.minimum(np.rint(np.abs(x)), 32767.0)
    return np.where(x < 0, -q, q).astype(np.int32)


@njit(parallel=True, cache=True)
def k_fix(A, B, drop, width):
    """A (T,K), B (K,N) int32 Q1.15. Each product (Q2.30) is truncated toward
    zero by `drop` bits and added into a `width`-bit saturating accumulator.
    Returns the accumulators and the number of clipped additions per row."""
    T, K = A.shape
    N = B.shape[1]
    out = np.empty((T, N), np.int64)
    clips = np.zeros(T, np.int64)
    lo = -(np.int64(1) << (width - 1))
    hi = (np.int64(1) << (width - 1)) - 1
    rnd = (np.int64(1) << drop) - 1
    for t in prange(T):
        acc = np.zeros(N, np.int64)
        c = 0
        for k in range(K):
            a = np.int64(A[t, k])
            if a == 0:
                continue
            for n in range(N):
                p = a * B[k, n]
                q = (p + ((p >> 63) & rnd)) >> drop        # truncate toward zero
                s = acc[n] + q
                r = min(max(s, lo), hi)
                c += s != r
                acc[n] = r
        for n in range(N):
            out[t, n] = acc[n]
        clips[t] = c
    return out, clips


def pop_sf16(acc: np.ndarray, frac_bits: int, e_in: int):
    """Round accumulators (value acc * 2**(e_in - frac_bits)) to SF16 with the
    output exponent that fits the largest. Round to nearest even on the
    magnitude, saturate. Returns floats."""
    v = acc.astype(np.float64) * (2.0 ** (e_in - frac_bits))
    eo = scale_exp(float(np.max(np.abs(v))) if v.size else 0.0)
    r = frac_bits - 15 + eo - e_in  # right shift of the integer accumulator
    if r <= 0:
        q = np.abs(acc).astype(np.float64) * (2.0 ** -r)
    else:
        q = np.rint(np.abs(acc).astype(np.float64) / (2.0 ** r))  # exact: < 2**53
    q = np.minimum(q, 32767.0)
    return np.where(acc < 0, -q, q) * (2.0 ** (eo - 15))


# -------------------------------------------------------------- FP16/BF16

FMTS = {
    # name: (mantissa bits, smallest normal exponent, largest exponent)
    "fp16": (10, -14, 15),
    "bf16": (7, -126, 127),
    "fp24": (15, -126, 127),
}


def fp_round(x: np.ndarray, fmt: str) -> np.ndarray:
    """Round to nearest even in fmt, FTZ before rounding, overflow to inf.
    Returns float64 values of the 16-bit words."""
    m, emin, emax = FMTS[fmt]
    x = np.asarray(x, dtype=np.float64)
    drop = 52 - m
    b = x.view(np.int64)
    half = np.int64((1 << (drop - 1)) - 1)
    r = (b + half + ((b >> drop) & 1)) & np.int64(~((1 << drop) - 1))
    y = r.view(np.float64)
    tiny = np.abs(x) < 2.0 ** emin
    y = np.where(tiny, np.copysign(0.0, x), y)
    maxf = (2.0 - 2.0 ** -m) * 2.0 ** emax
    y = np.where(np.abs(y) > maxf, np.copysign(np.inf, x), y)
    return np.where(np.isnan(x), np.nan, y)


@njit(parallel=True, cache=True)
def k_fpnat(A, B, m, emin, emax):
    """A, B float64 holding 16-bit values. acc = round(acc + a*b) per step."""
    T, K = A.shape
    N = B.shape[1]
    out = np.empty((T, N), np.float64)
    drop = 52 - m
    half = (np.int64(1) << (drop - 1)) - 1
    mask = ~((np.int64(1) << drop) - 1)
    tiny = 2.0 ** emin
    maxf = (2.0 - 2.0 ** (-m)) * 2.0 ** emax
    for t in prange(T):
        acc = np.zeros(N, np.float64)
        bits = acc.view(np.int64)
        for k in range(K):
            a = A[t, k]
            if a == 0.0:
                continue
            for n in range(N):
                acc[n] = acc[n] + a * B[k, n]
            for n in range(N):
                s = acc[n]
                if abs(s) < tiny:                  # tininess before rounding
                    acc[n] = 0.0 * s
                else:
                    b = bits[n]
                    bits[n] = (b + half + ((b >> drop) & 1)) & mask
                    if abs(acc[n]) > maxf:
                        acc[n] = math.copysign(math.inf, s)
        for n in range(N):
            out[t, n] = acc[n]
    return out


# ------------------------------------------------------------- dispatcher

class Case:
    """matmul(A, B, key) for one case. Weights (key not None) are quantized
    once and cached."""

    def __init__(self, name: str):
        assert name in CASES or name == "fp32", name
        self.name = name
        self.wcache = {}
        self.stats = {"clips": 0, "macs": 0, "headroom_bits": 0, "calls": 0}

    def _sf16_w(self, B, key):
        if key is not None and key in self.wcache:
            return self.wcache[key]
        e = scale_exp(float(np.max(np.abs(B))))
        r = (sf16_ints(B, e), e)
        if key is not None:
            self.wcache[key] = r
        return r

    def _fp_w(self, B, key, fmt):
        if key is not None and key in self.wcache:
            return self.wcache[key]
        r = np.ascontiguousarray(fp_round(B, fmt))
        if key is not None:
            self.wcache[key] = r
        return r

    def matmul(self, A, B, key=None):
        n = self.name
        T, K = A.shape
        self.stats["macs"] += T * K * B.shape[1]
        self.stats["calls"] += 1
        if n == "fp32":
            return (A.astype(np.float32) @ B.astype(np.float32)).astype(np.float32)
        if n.startswith("sf16"):
            frac, width = FIX[n]
            Bi, eb = self._sf16_w(B, key)
            ea = scale_exp(float(np.max(np.abs(A))))
            Ai = sf16_ints(A, ea)
            if n == "sf16_sat16h":
                exact = Ai.astype(np.float64) @ Bi.astype(np.float64)   # exact integers
                mx = float(np.max(np.abs(exact))) / 2.0 ** 30
                h = max(0, scale_exp(mx)) if mx >= 1.0 else 0
                if h:
                    ea += h
                    Ai = sf16_ints(A, ea)
                    self.stats["headroom_bits"] += h
            acc, clips = k_fix(Ai, Bi, 30 - frac, width)
            self.stats["clips"] += int(clips.sum())
            return pop_sf16(acc, frac, ea + eb).astype(np.float32)
        fmt, acc_kind = n.split("_")
        Bq = self._fp_w(B, key, fmt)
        Aq = np.ascontiguousarray(fp_round(A, fmt))
        if acc_kind == "fp32":
            r = Aq.astype(np.float32) @ Bq.astype(np.float32)
            return fp_round(r, fmt).astype(np.float32)
        m, emin, emax = FMTS[fmt if acc_kind == "nat" else acc_kind]
        r = k_fpnat(Aq, Bq, m, emin, emax)
        return (r if acc_kind == "nat" else fp_round(r, fmt)).astype(np.float32)
