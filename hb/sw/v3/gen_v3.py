#!/usr/bin/env python3
"""One v3 launch (prepare_v3.py's .npz) as the driver's launch.h.

  python3 gen_v3.py <launch.npz> <out.h>
"""
import sys

import numpy as np


def c_array(decl, values, per_line=24):
    v = [str(int(x)) for x in values]
    rows = [",".join(v[i:i + per_line]) for i in range(0, len(v), per_line)]
    return f"{decl} = {{\n" + ",\n".join(rows) + "\n};\n"


d = np.load(sys.argv[1])
T, K, N = int(d["T"]), int(d["K"]), int(d["N"])
with open(sys.argv[2], "w") as f:
    f.write(f'#define LAUNCH_NAME "{str(d["name"])}"\n#define T {T}\n#define K {K}\n#define N {N}\n#define SHIFT {int(d["shift"])}\n')
    sec = '__attribute__((section(".dram"), aligned(64)))'
    f.write(c_array(f"unsigned short A[T * K] {sec}", d["A"]))
    f.write(c_array(f"unsigned short Wt[K * N] {sec}", d["W"]))
    f.write(c_array(f"unsigned short Cexp[T * N] {sec}", d["C"]))
