#!/usr/bin/env python3
"""
YOLOv8n benchmark totals for one generation's three chips (docs/cnn_benchmark.md).

  cycles   every launch shape one image uses (schedule.py), simulated through
           the chip's pins in each format with every output checked bit for
           bit (results/<gen>_<fmt>.jsonl, from test_gpt2_bench.py runs of
           prepare.py's launches). A shape not simulated in a format is an
           error: no fit.
  clock    1 / (20 ns - worst setup slack) over the chip and its tile, from
           the signoff metrics (signoff/<fmt>/{chip,tile}).
  power    the gemm kernel's chip power at 50 MHz from gate-level activity of
           the signed-off netlists (test/gpt2/power/results/<fmt>_gemm.json),
           the kernel every convolution runs.
  energy   power x time at 50 MHz; dynamic power scales with the clock, so the
           energy per image does not depend on it.
  host     yolo.py's numpy time for the host's operations, on this machine.

v1's signoff metrics and power come from the cf-openframe branch (git show).

  python3 bench.py --gen v1 [--json results/summary_v1.json]
"""
import argparse
import json
import os
import subprocess
import sys
from collections import Counter

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
from yolo import Model, image                        # noqa: E402
from schedule import launches, conv_launches         # noqa: E402

FORMATS = ("sf16", "fp16", "bf16")
BRANCH = {"v1": "cf-openframe"}
LAUNCH_GAP = 7               # START low before / after a launch (test_gpt2_bench.run_launch)
SIGNOFF_PERIOD_NS = 20.0
POWER_CLOCK_MHZ = 50.0
PEAK_MACS = 4 * 64           # four tiles of 8 x 8 PEs


def source(gen, path):
    """A file of generation gen: from its branch for v1, else this tree."""
    if gen in BRANCH:
        return json.loads(subprocess.check_output(["git", "-C", REPO, "show", f"{BRANCH[gen]}:{path}"]))
    return json.load(open(os.path.join(REPO, path)))


def measured(gen, fmt):
    out = {}
    for line in open(os.path.join(HERE, "results", f"{gen}_{fmt}.jsonl")):
        r = json.loads(line)
        if r["mismatches"] or r["host_latency"] != 0:
            continue
        out[(r["kernel"], r["kc"], r["nb"])] = r
    return out


def peak_clock(gen, fmt, corner):
    ws = [source(gen, f"signoff/{fmt}/{blk}/final/metrics.json")[f"timing__setup__ws__corner:{corner}"]
          for blk in ("chip", "tile")]
    return 1e3 / (SIGNOFF_PERIOD_NS - min(ws)), ("tile" if ws[1] < ws[0] else "chip")


def power(gen, fmt):
    p = source(gen, f"test/gpt2/power/results/{fmt}_gemm.json")
    return p["top_w"] + 4 * p["tile_w"], p


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gen", default="v1")
    ap.add_argument("--json")
    args = ap.parse_args()
    gen = args.gen

    m = Model()
    m.forward(image())
    host = dict(m.host_s)
    ls = launches(m)
    shapes = Counter(ls)
    macs = sum(c.macs for c in m.convs)

    out = {"gen": gen, "model": "YOLOv8n 640x640", "convolutions": len(m.convs), "macs": macs,
           "weights": sum(c.cout * c.K for c in m.convs), "launches": len(ls), "shapes": len(shapes),
           "blocks": sum(nb for _, _, nb in ls), "host_s": host, "formats": {}}
    meas = {f: measured(gen, f) for f in FORMATS}
    missing = {f: [s for s in shapes if s not in meas[f]] for f in FORMATS}
    assert not any(missing.values()), f"shapes not simulated: {missing}"
    out["cycles_match"] = all(len({meas[f][s]["cycles"] for f in FORMATS}) == 1 for s in shapes)

    for fmt in FORMATS:
        cyc = sum((meas[fmt][s]["cycles"] + LAUNCH_GAP) * n for s, n in shapes.items())
        reads = sum(meas[fmt][s]["data_reads"] * n for s, n in shapes.items())
        writes = sum(meas[fmt][s]["writes"] * n for s, n in shapes.items())
        layers = {}
        for c in m.convs:
            layers[c.name] = sum(meas[fmt][s]["cycles"] + LAUNCH_GAP for s in conv_launches(c))
        f_ss, lim_ss = peak_clock(gen, fmt, "max_ss_100C_1v60")
        f_tt, lim_tt = peak_clock(gen, fmt, "nom_tt_025C_1v80")
        p50, pd = power(gen, fmt)
        r = {"cycles": cyc, "data_reads": reads, "writes": writes,
             "cycles_per_bus_beat": cyc / (reads + 2 * writes),
             "macs_per_cycle": macs / cyc, "utilisation": macs / cyc / PEAK_MACS,
             "fmax_ss_mhz": f_ss, "fmax_ss_limit": lim_ss, "fmax_tt_mhz": f_tt, "fmax_tt_limit": lim_tt,
             "power_50mhz_w": p50, "power_detail": pd,
             "energy_j": p50 * cyc / (POWER_CLOCK_MHZ * 1e6),
             "host_s": sum(host.values()), "layer_cycles": layers}
        for tag, f in (("ss", f_ss), ("tt", f_tt), ("50", POWER_CLOCK_MHZ)):
            t = cyc / (f * 1e6)
            r[tag] = {"clock_mhz": f, "chip_s": t, "image_s": t + r["host_s"],
                      "fps": 1.0 / (t + r["host_s"]), "power_w": p50 * f / POWER_CLOCK_MHZ}
        out["formats"][fmt] = r

    if args.json:
        os.makedirs(os.path.dirname(os.path.abspath(args.json)), exist_ok=True)
        json.dump(out, open(args.json, "w"), indent=1)
    report(out)


def report(out):
    print(f"{out['model']}: {out['convolutions']} convolutions, {out['macs'] / 1e9:.3f} GMACs, "
          f"{out['launches']} launches in {out['shapes']} shapes, {out['blocks']} blocks; "
          f"cycles identical in every format: {out['cycles_match']}")
    print(f"host per image: {sum(out['host_s'].values()) * 1e3:.0f} ms ("
          + ", ".join(f"{k} {v * 1e3:.0f}" for k, v in sorted(out['host_s'].items(), key=lambda kv: -kv[1])) + ")")
    for fmt, r in out["formats"].items():
        print(f"{fmt}: {r['cycles'] / 1e9:.3f} G cycles, {r['macs_per_cycle']:.3f} MAC/cycle "
              f"({100 * r['utilisation']:.3f}%), {r['cycles_per_bus_beat']:.2f} cycles/beat; "
              f"ss {r['fmax_ss_mhz']:.1f} MHz -> {r['ss']['image_s']:.1f} s/image; "
              f"tt {r['fmax_tt_mhz']:.1f} MHz -> {r['tt']['image_s']:.1f} s; "
              f"power {r['power_50mhz_w'] * 1e3:.1f} mW at 50 MHz, energy {r['energy_j']:.2f} J/image")


if __name__ == "__main__":
    main()
