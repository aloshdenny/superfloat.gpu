#!/usr/bin/env python3
"""
Power stimulus for the S2 blocks: real GPT-2 operands, the same real values
in every format. Layer 5's MLP input (c_fc) on a 1,024-token WikiText-2
window; four 8 x 8 weight tiles from c_fc's weights, 256 tokens each, the
next tile shifted in while the current one computes. Partial sums from the
north are the true sums over the K rows before the tile, in the
accumulator's format. Quantization follows study S1 (mxu_emu.py).

Writes stim/<variant>.txt (tb_block.sv's format) and stim/meta.json.
"""
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "s1"))
import mxu_emu as E                                       # noqa: E402
import s1_numerics as S1                                  # noqa: E402
from variants import VARIANTS, N, widths, latency         # noqa: E402

LAYER, M, TILE = 5, 1024, 256
TILES = [(384, 0), (392, 8), (400, 16), (408, 24)]        # (k0, n0)


def layer_input(w, ids):
    rec = {}

    def mm(A, B, key):
        if key == f"h.{LAYER}.c_fc":
            rec["A"] = A.copy()
        return A @ B
    S1.forward(w, ids, mm)
    return rec["A"].astype(np.float64)


def bits_fp(x, e, m):
    """Words of float64 values already representable in (e, m)."""
    f32 = x.astype(np.float32).view(np.uint32).astype(np.int64)
    if (e, m) == (5, 10):
        return x.astype(np.float16).view(np.uint16).astype(np.int64)
    return f32 >> (23 - m)                                  # e = 8: bf16, fp24, fp32


def main():
    w = S1.load_weights()
    toks = S1.tokens()
    A = layer_input(w, toks[:M])                           # (M, 768)
    W = w[f"h.{LAYER}.mlp.c_fc.weight"].astype(np.float64)  # (768, 3072)
    os.makedirs(os.path.join(HERE, "stim"), exist_ok=True)
    ea = E.scale_exp(float(np.abs(A).max()))
    ew = E.scale_exp(float(np.abs(W).max()))
    S = N + 2
    meta = {"layer": LAYER, "M": M, "tile_vectors": TILE, "tiles": TILES, "S": S, "variants": {}}
    for name, p in VARIANTS.items():
        iw, cw = widths(p)
        L = latency(p)
        if p["FMT"] == 0:
            def enc_in(x, e):
                q = E.sf16_ints(x, e).astype(np.int64)
                return np.where(q < 0, 0x8000 | -q, q)
            qa = enc_in(A, ea)
            qw = enc_in(W, ew)
            frac, width = p["FRAC"], p["ACC_W"]

            def enc_acc(P):
                q = np.rint(P / 2.0 ** (ea + ew) * 2.0 ** frac)
                q = np.clip(q, -(2 ** (width - 1)), 2 ** (width - 1) - 1).astype(np.int64)
                return q & ((1 << width) - 1)
        else:
            fin = "fp16" if p["IN_E"] == 5 else "bf16"
            qa = bits_fp(E.fp_round(A, fin), p["IN_E"], p["IN_M"])
            qw = bits_fp(E.fp_round(W, fin), p["IN_E"], p["IN_M"])
            acc = {(5, 10): "fp16", (8, 7): "bf16", (8, 15): "fp24", (8, 23): None}[(p["ACC_E"], p["ACC_M"])]

            def enc_acc(P, acc=acc, p=p):
                v = P.astype(np.float32).astype(np.float64) if acc is None else E.fp_round(P, acc)
                return bits_fp(v, p["ACC_E"], p["ACC_M"])
        T = S + M + 1
        rows = []
        pack = lambda v, b: "%x" % sum(int(x) << (i * b) for i, x in enumerate(v))
        for k in range(T):
            ti_next = None
            sh = sw = 0
            wn = [0] * N
            if k < N:                                          # first tile
                sh, ti_next, j = 1, 0, k
            for i in range(1, len(TILES)):
                b = S + TILE * i
                if b - 9 <= k < b - 1:
                    sh, ti_next, j = 1, i, k - (b - 9)
                if k == b:
                    sw = 1
            if k == N:
                sw = 1
            if sh:
                k0, n0 = TILES[ti_next]
                wn = qw[k0 + N - 1 - j, n0:n0 + N]
            aw = [0] * N
            for r in range(N):
                m = k - S - r * L
                if 0 <= m < M:
                    k0, n0 = TILES[min(m // TILE, len(TILES) - 1)]
                    aw[r] = qa[m, k0 + r]
            pn = [0] * N
            for c in range(N):
                m = k - S - 2 - c
                if 0 <= m < M:
                    k0, n0 = TILES[min(m // TILE, len(TILES) - 1)]
                    pn[c] = enc_acc(A[m:m + 1, :k0] @ W[:k0, n0 + c:n0 + c + 1])[0, 0]
            rows.append(f"{sh} {sw} {pack(aw, iw)} {pack(wn, iw)} {pack(pn, cw)}")
        open(os.path.join(HERE, "stim", f"{name}.txt"), "w").write("\n".join(rows) + "\n")
        # Every PE busy from the last row's first vector to the stream's end.
        meta["variants"][name] = {"L": L, "lines": T, "dump_from": S + N * L + 8, "dump_to": S + M - 1}
        print(name, T, "lines", flush=True)
    json.dump(meta, open(os.path.join(HERE, "stim", "meta.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
