#!/usr/bin/env python3
"""
The operands of one FP16 launch (test/gpt2/launches/fp16/<name>.npz) as FP32
arrays for the vanilla-core baseline (main.c):
  gemv: x (K), W (K x 8*NB, row-major), y_ref = x W
  gemm: A (K x 8, k-major: the 8 tokens of each k together), W, Y_ref = A^T W
        (8 x 8*NB, token-major)
References are in float64, for the tolerance check.

  python3 gen_vanilla.py <fp16 launch.npz> <out.h>
"""
import sys

import numpy as np

src, out = sys.argv[1], sys.argv[2]
d = np.load(src)
kernel, kc, nb = str(d["kernel"]), int(d["kc"]), int(d["nb"])
win = np.zeros(int(max(d["addr"].max(), d["exp_addr"].max())) + 1, dtype=np.uint16)
win[d["addr"]] = d["word"]
f = win.view(np.float16).astype(np.float32)
W = np.zeros((kc, 8 * nb), dtype=np.float32)
for b in range(nb):
    wbase = int(win[3 * b + 1])
    if kernel == "gemv":                          # per k block, rows 7..0
        w = f[wbase:wbase + 8 * kc].reshape(kc // 8, 8, 8)
        for k0 in range(kc // 8):
            for r in range(8):
                W[8 * k0 + r, 8 * b:8 * b + 8] = w[k0, 7 - r]
    else:                                         # per k, columns 0..7
        W[:, 8 * b:8 * b + 8] = f[wbase:wbase + 8 * kc].reshape(kc, 8)
xb = int(win[0])
if kernel == "gemv":
    x = f[xb:xb + kc]
    ref = x.astype(np.float64) @ W.astype(np.float64)
else:
    A = f[xb:xb + 8 * kc].reshape(kc, 8)           # kernel order: per k, tokens 0..7
    x = A.ravel()
    ref = (A.T.astype(np.float64) @ W.astype(np.float64)).ravel()


def arr(decl, v):
    return f"{decl} = {{" + ",".join(repr(float(a)) + "f" for a in v) + "};\n"


with open(out, "w") as h:
    h.write(f'#define LAUNCH_NAME "{src.split("/")[-1][:-4]}"\n#define GEMM {int(kernel == "gemm")}\n')
    h.write(f"#define K {kc}\n#define N {8 * nb}\n#define NB {nb}\n#define T {8 if kernel == 'gemm' else 1}\n")
    h.write(arr('float x[K * T] __attribute__((section(".dram")))', x))
    h.write(arr('float W[K * N] __attribute__((section(".dram")))', W.ravel()))
    h.write(arr('float y_ref[T * N] __attribute__((section(".dram")))', ref))
    h.write('float y[T * N] __attribute__((section(".dram")));\n')
