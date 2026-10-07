#!/usr/bin/env python3
"""
Bit-exact check of the S2 blocks (v3_variants.sv) against a Python model:
load an N x N weight tile, stream M random activation vectors with partial
sums from the north, and compare every psum_south word.

The FP reference is test/helpers/fp16fmt.py's exact Fraction FMA, with the
product in the input format and the addend and result in the accumulator's.

  python3 check_block.py [variant ...]        (default: all; M=200 vectors)
"""
import os
import random
import subprocess
import zlib
import sys
from fractions import Fraction

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "test", "helpers"))
import fp16fmt                                          # noqa: E402
from variants import VARIANTS, N, widths, latency, prod_stages      # noqa: E402

M = int(os.environ.get("M", "200"))
SRC = [os.path.join(ROOT, "src", "fp_arith.sv")] + [
    os.path.join(HERE, f) for f in ("csa_trees.sv", "fpx_align.sv", "v3_pe.sv", "v3_block.sv", "v3_variants.sv", "tb_block.sv")]


class Fmt(fp16fmt.Fmt):
    """fp16fmt.Fmt for any width (its decode masks 16 bits)."""

    def decode(self, bits):
        bits &= (1 << self.width) - 1
        s = bits >> (self.width - 1)
        ef = (bits >> self.m) & self.emax_field
        f = bits & ((1 << self.m) - 1)
        if ef == self.emax_field:
            return ("nan", 0, None) if f else ("inf", s, None)
        if ef == 0:
            return ("zero", s, Fraction(0))
        v = Fraction((1 << self.m) | f, 1 << self.m) * Fraction(2) ** (ef - self.bias)
        return ("num", s, -v if s else v)


def dropped(x, y, k):
    """The partial-product bits of x * y in columns below k (their sum)."""
    return sum(((y & ((1 << (k - i)) - 1)) << i) for i in range(k) if (x >> i) & 1)


def tmul(x, y, k, comp):
    """The truncated product: x * y without the columns below k, plus comp."""
    return x * y if k < 0 else x * y - dropped(x, y, k) + comp


def fma_mixed(fi, fa, a, b, c, k=-1, comp=0):
    """round_fa(a * b + c): a, b in fi, c and the result in fa. With k >= 0
    the significand product is truncated (tmul)."""
    ka, sa, va = fi.decode(a)
    kb, sb, vb = fi.decode(b)
    if k >= 0 and ka == "num" and kb == "num":
        ma = (1 << fi.m) | (a & ((1 << fi.m) - 1))
        mb = (1 << fi.m) | (b & ((1 << fi.m) - 1))
        ea = ((a >> fi.m) & fi.emax_field) - fi.bias
        eb = ((b >> fi.m) & fi.emax_field) - fi.bias
        mag = Fraction(tmul(ma, mb, k, comp)) * Fraction(2) ** (ea + eb - 2 * fi.m)
        va, vb = (-mag if sa ^ sb else mag), Fraction(1)
    kc, sc, vc = fa.decode(c)
    sp = sa ^ sb
    if "nan" in (ka, kb, kc):
        return fa.qnan
    p_inf = ka == "inf" or kb == "inf"
    p_zero = ka == "zero" or kb == "zero"
    if p_inf and p_zero:
        return fa.qnan
    if p_inf and kc == "inf" and sp != sc:
        return fa.qnan
    if p_inf:
        return fa.inf(sp)
    if kc == "inf":
        return fa.inf(sc)
    prod = Fraction(0) if p_zero else va * vb
    total = prod + (vc if kc == "num" else Fraction(0))
    if total == 0:
        if p_zero and kc == "zero":
            return fa.zero(sp & sc)
        return fa.zero(0)
    return fa.round_exact(total)


def sf_op(p, a, w, psum):
    frac, width = p["FRAC"], p["ACC_W"]
    mag = tmul(a & 0x7FFF, w & 0x7FFF, p.get("TRUNC_K", -1), p.get("COMP", 0)) >> (30 - frac)
    term = -mag if ((a ^ w) >> 15) & 1 else mag
    s = psum - (1 << width) if psum >> (width - 1) else psum        # signed
    s = max(min(s + term, (1 << (width - 1)) - 1), -(1 << (width - 1)))
    return s & ((1 << width) - 1)


def rand_sf(rng):
    m = rng.choice([rng.getrandbits(15), rng.getrandbits(15) >> rng.randrange(15), 0x7FFF, 0])
    return ((rng.getrandbits(1) << 15) | m) if m else 0          # canonical zero


def rand_fp(rng, f, center, spread):
    r = rng.random()
    s = rng.getrandbits(1)
    if r < 0.02:
        return f.zero(s)
    if r < 0.03:
        return f.inf(s)
    if r < 0.035:
        return f.qnan | (rng.getrandbits(f.m - 1))
    if r < 0.05:                                                     # subnormal field: reads as zero
        return (s << (f.width - 1)) | rng.randrange(1, 1 << f.m)
    if r < 0.08:                                                     # extremes: overflow and flush
        e = rng.choice([1, 2, f.emax_field - 1, f.emax_field - 2])
    else:
        e = min(max(center + rng.randint(-spread, spread), 1), f.emax_field - 1)
    return (s << (f.width - 1)) | (e << f.m) | rng.getrandbits(f.m)


def run(name):
    p = VARIANTS[name]
    iw, cw = widths(p)
    L = latency(p)
    P = prod_stages(p)
    rng = random.Random(zlib.crc32(name.encode()))
    if p["FMT"] == 0:
        rin = lambda: rand_sf(rng)
        racc = lambda: rng.choice([rng.getrandbits(cw), rng.getrandbits(cw) >> rng.randrange(cw),
                                   (1 << (cw - 1)) - 1 - rng.randrange(64), (1 << (cw - 1)) + rng.randrange(64)])
        op = lambda a, w, s: sf_op(p, a, w, s)
    else:
        fi = Fmt("in", p["IN_E"], p["IN_M"])
        fa = Fmt("acc", p["ACC_E"], p["ACC_M"])
        rin = lambda: rand_fp(rng, fi, fi.bias, 4)
        racc = lambda: rand_fp(rng, fa, fa.bias + rng.randint(-3, 3), 6)
        op = lambda a, w, s: fma_mixed(fi, fa, a, w, s, p.get("TRUNC_K", -1), p.get("COMP", 0))
    W = [[rin() for _ in range(N)] for _ in range(N)]
    A = [[rin() for _ in range(N)] for _ in range(M)]
    P0 = [[racc() for _ in range(N)] for _ in range(M)]
    S = N + 2
    T = S + M + N * L + N + 7 + P
    lines = []
    for k in range(T):
        sh = int(k < N)
        sw = int(k == N)
        wn = W[N - 1 - k] if k < N else [0] * N
        aw = [0] * N
        for r in range(N):
            m = k - S - r * L
            if 0 <= m < M:
                aw[r] = A[m][r]
        pn = [0] * N
        for c in range(N):
            m = k - S - 1 - P - c
            if 0 <= m < M:
                pn[c] = P0[m][c]
        pack = lambda v, b: "%x" % sum(x << (i * b) for i, x in enumerate(v))
        lines.append(f"{sh} {sw} {pack(aw, iw)} {pack(wn, iw)} {pack(pn, cw)}")
    work = os.path.join(HERE, "sim", name)
    os.makedirs(work, exist_ok=True)
    open(os.path.join(work, "stim.txt"), "w").write("\n".join(lines) + "\n")
    defs = [f"-DTOP=blk_{name}", f"-DIW={iw}", f"-DCW={cw}", f"-DN={N}"]
    subprocess.run(["iverilog", "-g2012", "-o", "sim.vvp", "-s", "tb_block"] + defs + SRC,
                   cwd=work, check=True)
    subprocess.run(["vvp", "-n", "sim.vvp"], cwd=work, check=True, stdout=subprocess.DEVNULL)
    out = [int(x, 16) if "x" not in x.lower() else None
           for x in open(os.path.join(work, "out.txt")).read().split()]
    bad = 0
    for m in range(M):
        for c in range(N):
            s = P0[m][c]
            for r in range(N):
                s = op(A[m][r], W[r][c], s)
            k = S + m + N * L + 2 + P + c
            got = None if out[k] is None else (out[k] >> (c * cw)) & ((1 << cw) - 1)
            if got != s:
                bad += 1
                if bad <= 3:
                    print(f"  {name} m={m} c={c}: got {got if got is None else hex(got)} want {hex(s)}")
    print(f"{name:14s} L={L} P={P}: {M * N - bad}/{M * N} outputs exact" + ("" if bad else "  OK"))
    return bad == 0


if __name__ == "__main__":
    names = sys.argv[1:] or list(VARIANTS)
    ok = all([run(n) for n in names])
    sys.exit(0 if ok else 1)
