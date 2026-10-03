#!/usr/bin/env python3
"""
Build chip launches of YOLOv8n operands, one per launch shape the schedule
uses (schedule.py), in the format of test/gpt2/prepare.py:

  ../gpt2/launches/<fmt>/yolo_gemm_<kc>_<nb>.npz   addr, word, exp_addr,
                                                   exp_word, kernel, kc, nb

Each takes a convolution with that K chunk from the synthetic-weight forward
pass (yolo.py): its first 8 output channels' weights (the shared operand)
and the patches of its first nb x 8 output pixels, and computes the
bit-exact outputs the kernel must store. test_gpt2_bench.py runs them:

  make test_gpt2_bench NUMBER_FORMAT=0 GPT2_LAUNCHES=yolo_gemm_576_13

  python3 prepare.py [shape ...]       (default: every shape of one image)
  FORMATS=sf16 python3 prepare.py yolo_gemm_576_13
"""
import os
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
GPT2 = os.path.join(os.path.dirname(HERE), "gpt2")
sys.path.insert(0, GPT2)
sys.path.insert(0, HERE)
from formats import NAMES, to_words, sf16_scale_exp, SF16        # noqa: E402
import kernels as K                                              # noqa: E402
from helpers.fp16fmt import BY_ID                                # noqa: E402
from yolo import Model, image                                    # noqa: E402
from schedule import chunks, launches, conv_launches             # noqa: E402

OUT = os.path.join(GPT2, "launches")


def encode(a, fmt):
    """Words of array a; SF16 uses one power-of-two scale per call."""
    if fmt == SF16:
        return to_words(a / (2.0 ** sf16_scale_exp(a)), SF16)
    return to_words(a, fmt)


def gemm_launch(fmt, A, Ws, kc):
    """A: 8 x kc, shared by every block; Ws: one kc x 8 operand per block."""
    win = K.Window()
    ref_fmt = BY_ID.get(fmt)
    abase = win.alloc_x(K.N * kc)
    awords = encode(A, fmt).tolist()
    win.put(abase, K.gemm_act_words(awords))
    blocks = []
    for W in Ws:
        words = encode(W, fmt).tolist()
        base = win.alloc(kc * K.N)
        win.put(base, K.gemm_weight_words(words, 0))
        blocks.append((base, words))
    exp = {}
    for wb, wwords in blocks:
        yb = win.alloc(K.N * K.N)
        win.add_block(abase, wb, yb)
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


def operands(model, kc, nb):
    """(A, [W per block]) for a launch shape: the first convolution with a K
    chunk of kc and at least nb pixel blocks."""
    for c in model.convs:
        if kc in chunks(c.K) and c.N // K.N >= nb:
            W, P = model.kept[c.name]
            Kp = kc * len(chunks(c.K))
            W = np.pad(W, ((0, 0), (0, Kp - c.K)))[:K.N, :kc]
            P = np.pad(P, ((0, Kp - c.K), (0, 0)))[:kc]
            return c.name, W, [P[:, K.N * b:K.N * (b + 1)] for b in range(nb)]
    raise ValueError(f"no convolution has a {kc} chunk and {nb} pixel blocks")


def main():
    fmts = [f for f, n in NAMES.items() if n in os.environ.get("FORMATS", "sf16,fp16,bf16").split(",")]
    m = Model(keep=())
    m.forward(image())
    m = Model(keep=[c.name for c in m.convs])
    m.forward(image())
    shapes = sorted(set(launches(m)), key=lambda s: (s[1], s[2]))
    names = sys.argv[1:] or [f"yolo_gemm_{kc}_{nb}" for _, kc, nb in shapes]
    for name in names:
        kc, nb = (int(v) for v in name.split("_")[-2:])
        src, A, Ws = operands(m, kc, nb)
        for fmt in fmts:
            t = time.time()
            win, exp = gemm_launch(fmt, A, Ws, kc)
            save(fmt, name, "gemm", kc, win, exp)
            print(f"{name} {NAMES[fmt]}: conv {src}, {len(win.data)} window words, "
                  f"{len(exp)} outputs, {time.time() - t:.1f} s")


if __name__ == "__main__":
    main()
