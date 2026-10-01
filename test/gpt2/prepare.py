#!/usr/bin/env python3
"""
Build the benchmark's chip launches from real GPT-2 operands.

Runs GPT-2 on a prompt (gpt2.py), takes the operands of selected matrix
multiplies, encodes them in SF16, FP16 and BF16 (formats.py), lays each
launch out in the chip's data window (kernels.Window) and computes the
bit-exact outputs the kernel must store. One .npz per launch and format:

  launches/<fmt>/<name>.npz   addr, word (window contents), exp_addr,
                              exp_word, kernel, kc, nb

test_gpt2_bench.py runs them through the chip's pins.

  python3 prepare.py [name ...]      (default: every launch below)
  FORMATS=sf16 python3 prepare.py shape_gemv_64_24   (any kernel_kc_nb shape)
"""
import os
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from formats import NAMES, to_words, sf16_scale_exp, SF16        # noqa: E402
from gpt2 import GPT2, tokenizer, new_cache, HEAD_DIM            # noqa: E402
import kernels as K                                              # noqa: E402
from helpers.fp16fmt import BY_ID                                # noqa: E402

PROMPT = ("The OpenFrame chip runs GPT-2 one layer at a time, streaming every "
          "weight from the host over a sixteen-bit bus.")
OUT = os.path.join(HERE, "launches")


def encode(a, fmt, exp=None):
    """Words of array a; SF16 uses one power-of-two scale per call."""
    if fmt == SF16:
        return to_words(a / (2.0 ** (sf16_scale_exp(a) if exp is None else exp)), SF16)
    return to_words(a, fmt)


def gemv_launch(fmt, blocks, kc):
    """blocks: (x, W) per block; x has kc values, W is kc x 8. Shared x
    arrays (same object) are stored once."""
    win = K.Window()
    ref_fmt = BY_ID.get(fmt)
    xs = {}
    xw, ww = [], []
    for x, W in blocks:
        if id(x) not in xs:
            base = win.alloc_x(kc)
            words = encode(x, fmt).tolist()
            win.put(base, words)
            xs[id(x)] = (base, words)
        xw.append(xs[id(x)])
    for x, W in blocks:
        words = encode(W, fmt)
        base = win.alloc(kc * K.N)
        win.put(base, K.gemv_weight_words(words.tolist(), 0))
        ww.append((base, words.tolist()))
    exp = {}
    for (xb, xwords), (wb, wwords) in zip(xw, ww):
        yb = win.alloc(K.N)
        win.add_block(xb, wb, yb)
        for j, y in enumerate(K.gemv_reference(xwords, wwords, 0, ref_fmt)):
            exp[yb + j] = y
    return win, exp


def gemm_launch(fmt, blocks, kc):
    """blocks: (A, W) per block; A is 8 x kc (8 tokens), W is kc x 8."""
    win = K.Window()
    ref_fmt = BY_ID.get(fmt)
    As = {}
    aw, ww = [], []
    for A, W in blocks:
        if id(A) not in As:
            base = win.alloc_x(K.N * kc)
            words = encode(A, fmt).tolist()
            win.put(base, K.gemm_act_words(words))
            As[id(A)] = (base, words)
        aw.append(As[id(A)])
    for A, W in blocks:
        words = encode(W, fmt).tolist()
        base = win.alloc(kc * K.N)
        win.put(base, K.gemm_weight_words(words, 0))
        ww.append((base, words))
    exp = {}
    for (ab, awords), (wb, wwords) in zip(aw, ww):
        yb = win.alloc(K.N * K.N)
        win.add_block(ab, wb, yb)
        for c, y in enumerate(K.gemm_reference(awords, wwords, 0, ref_fmt)):
            exp[yb + c] = y
    return win, exp


def save(fmt, name, kernel, kc, win, exp):
    d = os.path.join(OUT, NAMES[fmt])
    os.makedirs(d, exist_ok=True)
    addr = np.array(sorted(win.data), dtype=np.uint32)
    word = np.array([win.data[a] for a in addr], dtype=np.uint16)
    ea = np.array(sorted(exp), dtype=np.uint32)
    ew = np.array([exp[a] for a in ea], dtype=np.uint16)
    np.savez(os.path.join(d, name + ".npz"), addr=addr, word=word, exp_addr=ea, exp_word=ew,
             kernel=kernel, kc=kc, nb=len(win.blocks))


def specs(model, rec):
    """name -> (kernel, kc, blocks); blocks hold float operands."""
    W = model.W
    s = {}
    x0 = rec[(0, "c_attn")][-1]
    s["gemv_check"] = ("gemv", 64, [(x0[:64], W("h.0.attn.c_attn.weight")[:64, 8 * b:8 * b + 8]) for b in range(4)])
    A0 = rec[(0, "c_fc")][:8]
    s["gemm_check"] = ("gemm", 32, [(A0[:, :32], W("h.0.mlp.c_fc.weight")[:32, 8 * b:8 * b + 8]) for b in range(4)])
    # attention-style: every block its own x (two heads' queries)
    (q0, k0), (q1, k1) = rec[(0, "qk0")], rec[(0, "qk1")]
    s["gemv_heads_check"] = ("gemv", 64, [(q0[-1], k0[8 * b:8 * b + 8].T) for b in range(2)]
                             + [(q1[-1], k1[8 * b:8 * b + 8].T) for b in range(2)])
    xf = rec[(0, "c_fc")][-1]
    Wf = W("h.0.mlp.c_fc.weight")
    for nb in (10, 8, 6, 4, 3):
        s[f"gemv_768_{nb}"] = ("gemv", 768, [(xf, Wf[:, 8 * b:8 * b + 8]) for b in range(nb)])
    for nb in (9, 8, 6, 4):
        s[f"gemm_768_{nb}"] = ("gemm", 768, [(A0, Wf[:, 8 * b:8 * b + 8]) for b in range(nb)])

    # Attention. Decode: scores are a gemv per head with x = q (64) and W =
    # K^T (64 x 8 positions per block); attention x V is a gemv with x = the
    # head's probabilities (context length) and W = V (8 head dims per block).
    # Prefill: the same as gemm over 8 query tokens. Every block of a head
    # shares that head's x. The prompt's K and V (layers 0-1) fill the
    # positions; cycles do not depend on the values.
    heads = range(12)
    qk = [rec[(0, f"qk{h}")] for h in heads]
    av = [rec[(0, f"av{h}")] for h in heads]
    Kc = [np.concatenate([qk[h][1], rec[(1, f"qk{h}")][1]]) for h in heads]   # 56 positions
    Vc = [np.concatenate([av[h][1], rec[(1, f"av{h}")][1]]) for h in heads]
    q_last = [qk[h][0][-1] for h in heads]
    q8 = [qk[h][0][:8] for h in heads]

    def score_blocks(qs, nb):
        return [(qs[b % 12], Kc[b % 12][8 * (b // 12):8 * (b // 12) + 8].T) for b in range(nb)]

    for nb in (31, 12):
        s[f"att_qk_64_{nb}"] = ("gemv", 64, score_blocks(q_last, nb))
        s[f"pf_qk_64_{nb}"] = ("gemm", 64, score_blocks(q8, nb))
    for L in (16, 48):
        p_last = [np.resize(av[h][0][-1], L) for h in heads]
        p8 = [np.resize(av[h][0][:8], (8, L)) for h in heads]
        for nb in (31, 3):
            blocks = [(p_last[b // 8 % 12], Vc[b // 8 % 12][:L, 8 * (b % 8):8 * (b % 8) + 8]) for b in range(nb)]
            s[f"att_av_{L}_{nb}"] = ("gemv", L, blocks)
            blocks8 = [(p8[b // 8 % 12], Vc[b // 8 % 12][:L, 8 * (b % 8):8 * (b % 8) + 8]) for b in range(nb)]
            s[f"pf_av_{L}_{nb}"] = ("gemm", L, blocks8)
    return s


def shape_spec(model, rec, name):
    """A launch of a given shape for cycle measurement: 'shape_<kernel>_<kc>_<nb>'.
    Operands are real (layer 0's FC1 weights and its input), cut or repeated
    to kc; every block shares one x/A. Cycles do not depend on the values."""
    _, kernel, kc, nb = name.split("_")
    kc, nb = int(kc), int(nb)
    Wf = model.W("h.0.mlp.c_fc.weight")
    W = np.resize(Wf[:, :8 * nb].T, (8 * nb, kc)).T             # kc x 8nb
    if kernel == "gemv":
        x = np.resize(rec[(0, "c_fc")][-1], kc)
        return kernel, kc, [(x, W[:, 8 * b:8 * b + 8]) for b in range(nb)]
    A = np.resize(rec[(0, "c_fc")][:8], (8, kc))
    return kernel, kc, [(A, W[:, 8 * b:8 * b + 8]) for b in range(nb)]


def main():
    want = set(sys.argv[1:])
    fmts = [f for f, n in NAMES.items() if n in os.environ.get("FORMATS", "sf16,fp16,bf16").split(",")]
    t0 = time.time()
    model = GPT2()
    ids = tokenizer().encode(PROMPT).ids
    rec = {}
    model.forward(ids, new_cache(), record=rec)
    print(f"GPT-2 forward on {len(ids)} prompt tokens: {time.time() - t0:.1f} s")
    todo = specs(model, rec)
    for name in sorted(n for n in want if n.startswith("shape_")):
        todo[name] = shape_spec(model, rec, name)
    for name, (kernel, kc, blocks) in todo.items():
        if want and name not in want:
            continue
        for fmt in fmts:
            t = time.time()
            win, exp = (gemv_launch if kernel == "gemv" else gemm_launch)(fmt, blocks, kc)
            save(fmt, name, kernel, kc, win, exp)
            print(f"  {NAMES[fmt]} {name}: {len(win.blocks)} blocks, window {win.top} words, "
                  f"{time.time() - t:.1f} s")


if __name__ == "__main__":
    main()
