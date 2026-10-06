#!/usr/bin/env python3
"""Figure for docs/hammerblade.md: GPT-2 decode per token, 32-token prompt,
on the OpenFrame chip and on HammerBlade (direct adapter, read buffer), per
format: time at the tile's peak clock, and energy.

  python3 hb/make_fig.py   -> hb/results/gpt2_hammerblade.png
"""
import json
import os
import statistics

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt                       # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
hb = json.load(open(os.path.join(HERE, "results", "summary.json")))["formats"]
chip = json.load(open(os.path.join(HERE, "..", "test", "gpt2", "results", "summary.json")))["formats"]
FMTS, P = ("sf16", "fp16", "bf16"), "32"
INK, MUTED = "#1F3A5F", "#5B6B7F"
SERIES = [("OpenFrame chip (16-bit pin bus)", "#B9C4D0"),
          ("HammerBlade, direct adapter", "#5B8DB8"),
          ("HammerBlade, read buffer", INK)]
plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 10, "text.color": INK,
                     "axes.edgecolor": MUTED, "axes.labelcolor": INK, "xtick.color": INK, "ytick.color": INK})

tpot, energy = [], []
for f in FMTS:
    c = chip[f]["scenarios"][P]["ss"]
    tpot.append([statistics.mean(c["tpot_s"]), hb[f]["scenarios"][P]["tpot_s"], hb[f + "_rb"]["scenarios"][P]["tpot_s"]])
    energy.append([statistics.mean(c["energy_decode_j"]), hb[f]["scenarios"][P]["tile_energy_per_decode_token_j"],
                   hb[f + "_rb"]["scenarios"][P]["tile_energy_per_decode_token_j"]])

fig, axes = plt.subplots(1, 2, figsize=(10, 4.2))
w = 0.26
for ax, data, title, unit in ((axes[0], tpot, "Time per output token", "s"),
                              (axes[1], energy, "Energy per output token", "J")):
    for s, (label, color) in enumerate(SERIES):
        xs = [i + (s - 1) * w for i in range(len(FMTS))]
        vals = [d[s] for d in data]
        bars = ax.bar(xs, vals, w - 0.03, color=color, label=label)
        for b, v in zip(bars, vals):
            ax.text(b.get_x() + b.get_width() / 2, v + max(max(d) for d in data) * 0.01, f"{v:.1f}",
                    ha="center", va="bottom", fontsize=8, color=INK)
    ax.set_xticks(range(len(FMTS)))
    ax.set_xticklabels([f.upper() for f in FMTS])
    ax.set_ylabel(unit)
    ax.set_title(title, fontsize=11, weight="bold", loc="left")
    ax.grid(axis="y", color="#E3E8EE", linewidth=0.8)
    ax.set_axisbelow(True)
    for sp in ("top", "right"):
        ax.spines[sp].set_visible(False)
h, l = axes[0].get_legend_handles_labels()
fig.legend(h, l, frameon=False, fontsize=9, loc="upper center", ncol=3, bbox_to_anchor=(0.5, 0.925))
fig.suptitle("GPT-2 small decode, 32-token prompt: four v1 tiles per format, at each tile's SKY130 peak clock",
             fontsize=11, weight="bold")
fig.text(0.01, 0.01, "Cycles measured on RTL (bit-exact). Clock and power: SKY130 tile signoff. Energy: four tiles "
         "(chip: tiles + top level); HammerBlade mesh, caches and DRAM not included.", fontsize=7.5, color=MUTED)
fig.tight_layout(rect=(0, 0.04, 1, 0.87))
out = os.path.join(HERE, "results", "gpt2_hammerblade.png")
fig.savefig(out, dpi=180, facecolor="white")
print(out)
