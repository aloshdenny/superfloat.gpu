#!/usr/bin/env python3
"""
GPT-2 launches for the v3 matrix tile (hb/v/sf_hb_v3.sv): every matrix
multiply of a T-token prompt's prefill, with real operands (layer 0 of
GPT-2 small on the benchmark prompt) and the bit-exact results the tile must
store, from study S1's matrix-unit emulator (v3/s1/mxu_emu.py, copied as
hb/sw/v3/mxu_emu.py): products accumulated along K in order in the
format's accumulator, one rounding at the pop.

  sf16  SF24 (Q5.19), truncated product (K 9, COMP 1024); pop: shift right
        by the output scale's SHIFT, round to nearest even, saturate
  fp16  FP24 (1/8/15), truncated significand product (K 4, COMP 12)
  bf16  FP24
One launch per shape: qkv, proj, fc1, fc2, and head 0's scores and
attention x V (the other heads have the same shape), named <shape>_t<T>;
and the LM head, the last token's 768 x 50,257 GEMV, on its first 2,048 and
4,096 columns (lmhead_c2048, lmhead_c4096: the tile's cycles grow with the
number of column blocks, so two points give the line to 50,257).

  NA=8 python3 prepare_v3.py <out dir> <T> [T ...]   -> <out>/<fmt>/<name>.npz
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "test", "gpt2"))
import mxu_emu as E                                                 # noqa: E402
from gpt2 import GPT2, tokenizer, new_cache                        # noqa: E402

PROMPT = ("The OpenFrame chip runs GPT-2 one layer at a time, streaming every "
          "weight from the host over a sixteen-bit bus.")
LM_COLS = (2048, 4096)
NA = int(os.environ.get("NA", "8"))              # the tile's array size: W is laid out in NA x NA tiles


def sf16_words(q):
    return np.where(q < 0, 0x8000 | (-q), q).astype(np.uint16)


def fp_words(x, fmt):
    if fmt == "fp16":
        return x.astype(np.float16).view(np.uint16)
    return (x.astype(np.float32).view(np.uint32) >> 16).astype(np.uint16)


def launch(A, W, fmt):
    """(A words, W words, C words, shift) for C = A W in fmt."""
    A = np.ascontiguousarray(A, dtype=np.float64)
    W = np.ascontiguousarray(W, dtype=np.float64)
    if fmt == "sf16":
        ea, ew = E.scale_exp(float(np.abs(A).max())), E.scale_exp(float(np.abs(W).max()))
        Ai, Wi = E.sf16_ints(A, ea), E.sf16_ints(W, ew)
        acc, _ = E.k_fix_t(Ai, Wi, 30 - 19, 24, 9, 1024)
        v = acc.astype(np.float64) * 2.0 ** (ea + ew - 19)
        eo = E.scale_exp(float(np.abs(v).max()) if v.size else 0.0)
        r = 19 - 15 + eo - (ea + ew)
        mag = np.abs(acc).astype(np.float64)
        q = mag * 2.0 ** (-r) if r <= 0 else np.rint(mag / 2.0 ** r)
        q = np.minimum(q, 32767.0).astype(np.int64)
        q = np.where(acc < 0, -q, q)
        return sf16_words(Ai.astype(np.int64)), sf16_words(Wi.astype(np.int64)), sf16_words(q), r
    Aq, Wq = E.fp_round(A, fmt), E.fp_round(W, fmt)
    if fmt == "fp16":
        MA, EA = E.sig_exp(Aq, 10)
        MB, EB = E.sig_exp(Wq, 10)
        acc = E.k_fpnat_t(MA, EA, MB, EB, 4, 12, *E.FMTS["fp24"])
    else:
        acc = E.k_fpnat(np.ascontiguousarray(Aq), np.ascontiguousarray(Wq), *E.FMTS["fp24"])
    return fp_words(Aq, fmt), fp_words(Wq, fmt), fp_words(E.fp_round(acc, fmt), fmt), 0


def tiles(Ww, na=8):
    """K x N words in tile order: tile (cb, kb) = rows kb*na.., cols cb*na..,
    at index cb * K/na + kb, row-major."""
    K, N = Ww.shape
    return Ww.reshape(K // na, na, N // na, na).transpose(2, 0, 1, 3).reshape(-1)


def shapes(model, T):
    ids = (tokenizer().encode(PROMPT).ids * 64)[:T]
    rec = {}
    model.forward(ids, new_cache(), record=rec)
    w = model.W
    qh, Kh = rec[(0, "qk0")]
    pr, Vh = rec[(0, "av0")]
    return {
        "qkv": (rec[(0, "c_attn")], w("h.0.attn.c_attn.weight")),
        "proj": (rec[(0, "attn_proj")], w("h.0.attn.c_proj.weight")),
        "fc1": (rec[(0, "c_fc")], w("h.0.mlp.c_fc.weight")),
        "fc2": (rec[(0, "mlp_proj")], w("h.0.mlp.c_proj.weight")),
        "scores": (qh, Kh.T),
        "av": (pr, Vh),
    }, rec[(12, "lm_head")]


def main():
    out, Ts = sys.argv[1], [int(t) for t in sys.argv[2:]]
    model = GPT2()
    jobs = []
    for T in Ts:
        sh, lm_in = shapes(model, T)
        jobs += [(f"{name}_t{T}", A, W) for name, (A, W) in sh.items()]
    jobs += [(f"lmhead_c{n}", lm_in, model.W("wte.weight").T[:, :n]) for n in LM_COLS]
    if True:
        for name, A, W in jobs:
            for fmt in ("sf16", "fp16", "bf16"):
                aw, ww, cw, r = launch(A, W, fmt)
                d = os.path.join(out, fmt)
                os.makedirs(d, exist_ok=True)
                Tm, K = A.shape
                N = W.shape[1]
                np.savez(os.path.join(d, f"{name}.npz"), A=aw.reshape(-1), W=tiles(ww.reshape(K, N), NA),
                         C=cw.reshape(-1), T=Tm, K=K, N=N, shift=r, name=name)
                print(f"{fmt} {name}: T {Tm} K {K} N {N} shift {r}", flush=True)


if __name__ == "__main__":
    main()
