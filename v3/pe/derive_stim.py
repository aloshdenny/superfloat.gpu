#!/usr/bin/env python3
"""Stimulus for the lever variants (variants.ROUND2) from the base variants'
(power_stim.py): the same real operands, so the same words, except SF28,
whose partial sums are SF32's re-packed in 28-bit lanes (same Q.23 values,
clamped to Q5.23). Writes stim/<variant>.txt and adds them to stim/meta.json."""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
S = os.path.join(HERE, "stim")
N = 8
BASE = {"sf16_sf24_m": "sf16_sf24", "sf16_sf24_t": "sf16_sf24", "sf16_sf24_tg": "sf16_sf24",
        "sf16_sf28": "sf16_sf32", "sf16_sf28_t": "sf16_sf32", "sf16_sf28_tg": "sf16_sf32",
        "sf16_sf32_m": "sf16_sf32", "sf16_sf32_t": "sf16_sf32", "sf16_sf32_tg": "sf16_sf32",
        "fp16_fp24_a_m": "fp16_fp24_a", "fp16_fp24_a_t": "fp16_fp24_a", "fp16_fp24_a_tg": "fp16_fp24_a",
        "bf16_fp24_a_g": "bf16_fp24_a"}
meta = json.load(open(os.path.join(S, "meta.json")))


def repack(hexs, w_in, w_out):
    v = int(hexs, 16)
    out = 0
    for i in range(N):
        x = (v >> (i * w_in)) & ((1 << w_in) - 1)
        x = x - (1 << w_in) if x >> (w_in - 1) else x
        x = max(min(x, (1 << (w_out - 1)) - 1), -(1 << (w_out - 1)))
        out |= (x & ((1 << w_out) - 1)) << (i * w_out)
    return "%x" % out


for name, base in BASE.items():
    lines = open(os.path.join(S, base + ".txt")).read().split("\n")
    if name.startswith("sf16_sf28"):
        new = []
        for l in lines:
            f = l.split()
            if len(f) == 5:
                f[4] = repack(f[4], 32, 28)
                l = " ".join(f)
            new.append(l)
        lines = new
    open(os.path.join(S, name + ".txt"), "w").write("\n".join(lines))
    meta["variants"][name] = dict(meta["variants"][base])
json.dump(meta, open(os.path.join(S, "meta.json"), "w"), indent=1)
print(len(meta["variants"]), "variants in meta")
