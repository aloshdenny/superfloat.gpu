#!/usr/bin/env python3
"""
Export a benchmark launch (gpt2/launches/<fmt>/<name>.npz) as the hex images
tb_chip_power.v loads: prog.hex (512 words), data.hex (64K words), the
thread count and the expected outputs (expected.txt: "addr word" per line).

  python3 image.py <fmt> <name> <out dir>
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import kernels as K                                       # noqa: E402


def main(fmt: str, name: str, out: str) -> None:
    z = np.load(os.path.join(os.path.dirname(HERE), "launches", fmt, name + ".npz"))
    kc, kernel = int(z["kc"]), str(z["kernel"])
    prog = K.gemv_program(kc) if kernel == "gemv" else K.gemm_program(kc)
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "prog.hex"), "w") as f:
        f.write("\n".join(f"{w:04x}" for w in prog + [0] * (512 - len(prog))) + "\n")
    data = np.zeros(1 << 16, dtype=np.uint16)
    data[z["addr"]] = z["word"]
    with open(os.path.join(out, "data.hex"), "w") as f:
        f.write("\n".join(f"{int(w):04x}" for w in data) + "\n")
    with open(os.path.join(out, "expected.txt"), "w") as f:
        f.write("\n".join(f"{int(a)} {int(w)}" for a, w in zip(z["exp_addr"], z["exp_word"])) + "\n")
    with open(os.path.join(out, "launch.env"), "w") as f:
        f.write(f"THREADS={8 * int(z['nb'])}\nKERNEL={kernel}\nKC={kc}\nNB={int(z['nb'])}\n")
    print(f"{fmt} {name}: {kernel} kc={kc} nb={int(z['nb'])} -> {out}")


if __name__ == "__main__":
    main(*sys.argv[1:4])
