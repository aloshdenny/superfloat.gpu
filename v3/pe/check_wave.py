#!/usr/bin/env python3
"""
Bit-exact check of the wavefront weight swap (WAVE = 1, v3_block.sv): PASSES
weight tiles streamed back to back, each with T activation vectors, under
the tightest schedule the HammerBlade matrix tile uses (hb/v3):

  s_p     first w_shift cycle of tile p (w_north rows N-1 .. 0)
  t0_p    row 0's first activation (and swap token) of pass p
  row r's activations of pass p:  cycles t0_p + r L + t, t < T
  psum into column c:            cycle t0_p + t + 1 + P + c
  result out of column c:        after the edge of cycle t0_p + t + N L + 2 + P + c
  s_0 = 0, t0_p >= s_p + N, t0_p >= t0_(p-1) + T,
  s_p >= t0_(p-1) + (N - 1)(L + 1)   (every PE has copied tile p-1 in)

  python3 check_wave.py [variant ...]     (default: every WAVE variant)
"""
import os
import random
import subprocess
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import check_block as CB                                           # noqa: E402
from variants import VARIANTS, WAVE, N, widths, latency, prod_stages  # noqa: E402

PASSES = int(os.environ.get("PASSES", "6"))
EARLY = int(os.environ.get("EARLY", "0"))        # shift this many cycles too early (must fail)


def schedule(T, L, passes):
    s, t0 = [0], [N]
    for p in range(1, passes):
        s.append(t0[-1] + (N - 1) * (L + 1) - EARLY)
        t0.append(max(s[-1] + N, t0[-1] + T))
    return s, t0


def run(name, T):
    p = VARIANTS[name]
    iw, cw = widths(p)
    L, P = latency(p), prod_stages(p)
    rng = random.Random(zlib.crc32(f"{name}{T}".encode()))
    if p["FMT"] == 0:
        rin = lambda: CB.rand_sf(rng)
        racc = lambda: rng.choice([rng.getrandbits(cw), rng.getrandbits(cw) >> rng.randrange(cw)])
        op = lambda a, w, s: CB.sf_op(p, a, w, s)
    else:
        fi = CB.Fmt("in", p["IN_E"], p["IN_M"])
        fa = CB.Fmt("acc", p["ACC_E"], p["ACC_M"])
        rin = lambda: CB.rand_fp(rng, fi, fi.bias, 4)
        racc = lambda: CB.rand_fp(rng, fa, fa.bias + rng.randint(-3, 3), 6)
        op = lambda a, w, s: CB.fma_mixed(fi, fa, a, w, s, p.get("TRUNC_K", -1), p.get("COMP", 0))
    W = [[[rin() for _ in range(N)] for _ in range(N)] for _ in range(PASSES)]
    A = [[[rin() for _ in range(N)] for _ in range(T)] for _ in range(PASSES)]
    P0 = [[[racc() for _ in range(N)] for _ in range(T)] for _ in range(PASSES)]
    s, t0 = schedule(T, L, PASSES)
    end = t0[-1] + T + N * L + 2 + P + N + 4
    sh = [0] * end
    wn = [[0] * N for _ in range(end)]
    aw = [[0] * N for _ in range(end)]
    tok = [[0] * N for _ in range(end)]
    pn = [[0] * N for _ in range(end)]
    for q in range(PASSES):
        for j in range(N):
            sh[s[q] + j] = 1
            wn[s[q] + j] = W[q][N - 1 - j]
        for r in range(N):
            for t in range(T):
                aw[t0[q] + r * L + t][r] = A[q][t][r]
            tok[t0[q] + r * L][r] = 1
        for c in range(N):
            for t in range(T):
                pn[t0[q] + t + 1 + P + c][c] = P0[q][t][c]
    pack = lambda v, b: "%x" % sum(x << (i * b) for i, x in enumerate(v))
    lines = [f"{sh[k]} 0 {pack(aw[k], iw)} {pack(wn[k], iw)} {pack(pn[k], cw)} {pack(tok[k], 1)}" for k in range(end)]
    work = os.path.join(HERE, "sim", f"wave_{name}_{T}")
    os.makedirs(work, exist_ok=True)
    open(os.path.join(work, "stim.txt"), "w").write("\n".join(lines) + "\n")
    src = [f for f in CB.SRC if not f.endswith("tb_block.sv")] + [os.path.join(HERE, "tb_wave.sv")]
    defs = [f"-DTOP=blk_{name}", f"-DIW={iw}", f"-DCW={cw}", f"-DN={N}"]
    subprocess.run(["iverilog", "-g2012", "-o", "sim.vvp", "-s", "tb_wave"] + defs + src, cwd=work, check=True)
    subprocess.run(["vvp", "-n", "sim.vvp"], cwd=work, check=True, stdout=subprocess.DEVNULL)
    out = open(os.path.join(work, "out.txt")).read().split()

    def lane(k, c):
        b = out[k][len(out[k]) - (c + 1) * cw:len(out[k]) - c * cw]
        return None if any(ch not in "01" for ch in b) else int(b, 2)
    bad = n = 0
    for q in range(PASSES):
        for t in range(T):
            for c in range(N):
                acc = P0[q][t][c]
                for r in range(N):
                    acc = op(A[q][t][r], W[q][r][c], acc)
                k = t0[q] + t + N * L + 2 + P + c
                got = lane(k, c)
                n += 1
                if got != acc:
                    bad += 1
                    if bad <= 3:
                        print(f"  {name} T={T} pass {q} t={t} c={c}: got {got} want {hex(acc)}")
    period = t0[1] - t0[0] if PASSES > 1 else 0
    print(f"{name:20s} T={T:3d} L={L} P={P}: {n - bad}/{n} exact, pass period {period}" + ("" if bad else "  OK"))
    return bad == 0


if __name__ == "__main__":
    names = sys.argv[1:] or WAVE
    ok = all([run(n, T) for n in names for T in (8, 32)])
    sys.exit(0 if ok else 1)
