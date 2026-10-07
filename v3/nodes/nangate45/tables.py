#!/usr/bin/env python3
"""Markdown tables for nangate45.md from s2.json (../../pe/collect_s2.py
nangate45 <iso_ps> <max_ps>), with the 2 nm figures for the comparison
variants if a GT2N s2.json is given.

  tables.py [gt2n_s2.json]

Per variant, at the iso-clock period T (its run):
  area/MAC    standard-cell area / 64          energy/MAC  P x T / 64
  TFLOPS/mm2  2 FLOPs / T / area per MAC       TFLOPS/W    2 FLOPs / energy per MAC
  max clock   1 / (T_max - reg-to-reg slack), from the max-clock run
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "pe"))
from variants import VARIANTS, latency          # noqa: E402

S = json.load(open(os.path.join(HERE, "s2.json")))
ISO, MAXP, D = S["iso_period_ps"], S["max_period_ps"], S["variants"]
SFX = f"{ISO}ps"
G2 = json.load(open(sys.argv[1])) if len(sys.argv) > 1 else {}
REP = os.path.join(HERE, "..", "..", "pe", "results", "nangate45", "reports")

NAMES = {
    "sf16_sat16": "SF16, 16-bit (v2)", "sf16_sf24": "SF16, SF24", "sf16_sf32": "SF16, SF32",
    "fp16_fp16": "FP16, native", "fp16_fp24": "FP16, FP24", "fp16_fp32": "FP16, FP32",
    "bf16_bf16": "BF16, native", "bf16_fp24": "BF16, FP24", "bf16_fp32": "BF16, FP32",
    "fp16_fp16_a": "FP16, native (a)", "fp16_fp24_a": "FP16, FP24 (a)", "fp16_fp32_a": "FP16, FP32 (a)",
    "bf16_bf16_a": "BF16, native (a)", "bf16_fp24_a": "BF16, FP24 (a)", "bf16_fp32_a": "BF16, FP32 (a)",
    "sf16_sf24_m": "SF16, SF24, rows (none dropped)", "sf16_sf24_t": "SF16, SF24, truncated",
    "sf16_sf24_tg": "SF16, SF24, truncated + gated", "sf16_sf28": "SF16, SF28",
    "sf16_sf28_t": "SF16, SF28, truncated", "sf16_sf28_tg": "SF16, SF28, truncated + gated",
    "sf16_sf32_m": "SF16, SF32, rows (none dropped)", "sf16_sf32_t": "SF16, SF32, truncated",
    "sf16_sf32_tg": "SF16, SF32, truncated + gated", "fp16_fp24_a_m": "FP16, FP24 (a), rows (none dropped)",
    "fp16_fp24_a_t": "FP16, FP24 (a), truncated", "fp16_fp24_a_tg": "FP16, FP24 (a), truncated + gated",
    "bf16_fp24_a_g": "BF16, FP24 (a), gated",
}
CMP = ["sf16_sf24_tg", "sf16_sf28_tg", "fp16_fp24_a_tg", "bf16_fp24_a_g"]
BOLD = set(CMP)


def f(x, p):
    return (p % x) if x is not None else "–"


def row(v):
    r = D.get(v, {})
    t = r.get("nangate45", {}).get(str(ISO), {})
    return dict(area=r.get("area_per_mac_um2"), energy=r.get("energy_per_mac_fj"),
                tfmm2=r.get(f"tflops_per_mm2_{SFX}"), tfw=r.get("tflops_per_w"),
                fmax=r.get("fmax_ghz"), capped=r.get("fmax_capped"), meets=r.get(f"meets_{SFX}"),
                slack=t.get("r2r_slack_ps"), equiv=t.get("equiv"), pins=t.get("annotated_pins"),
                regs=t.get("regs"), mw=r.get(f"power_mw_{SFX}"))


def probe():
    """Reg-to-reg slack and area of the comparison variants at each probe
    period, from the report files (results/nangate45/reports, not in git)."""
    import re
    ps = sorted({int(m.group(1)) for f in os.listdir(REP) for m in [re.match(r"sf16_sf24_tg_(\d+)\.txt$", f)] if m})
    ps = [p for p in ps if p >= ISO * 0.6]
    print("## Iso-clock probe: register-to-register slack (ps) at global route\n")
    print("| Variant | " + " | ".join(f"{p / 1e3:g} ns" for p in ps) + " |")
    print("|---|" + "---|" * len(ps))
    for v in CMP:
        cells = []
        for p in ps:
            f = os.path.join(REP, f"{v}_{p}.txt")
            t = open(f).read() if os.path.exists(f) else ""
            m = re.search(r"REG2REG.*?\s(-?[\d.]+) \((MET|VIOLATED)\)", t, re.S)
            cells.append("–" if not m else f"{float(m.group(1)) * 1e3:+.1f}" + (" (met)" if m.group(2) == "MET" else ""))
        print(f"| {NAMES[v]} | " + " | ".join(cells) + " |")
    print()


if os.path.isdir(REP):
    probe()

print(f"## All variants at {ISO} ps ({1e3 / ISO:.3f} GHz); max clock from the {MAXP} ps run\n")
print(f"| Variant at {ISO / 1e3:g} ns | Stages | Meets {ISO / 1e3:g} ns | Area/MAC (µm²) | Energy/MAC (fJ) "
      "| TFLOPS/mm² | TFLOPS/W | Max clock (GHz) |")
print("|---|---|---|---|---|---|---|---|")
for v in VARIANTS:
    a = row(v)
    b = "**" if v in BOLD else ""
    m = "–" if a["meets"] is None else ("yes" if a["meets"] else "no")
    fm = f(a["fmax"], "%.2f") + (" (≥, met)" if a["capped"] else "")
    print(f"| {b}{NAMES[v]}{b} | {latency(VARIANTS[v])} | {m} | {b}{f(a['area'], '%.0f')}{b} | {b}{f(a['energy'], '%.0f')}{b} "
          f"| {b}{f(a['tfmm2'], '%.2f')}{b} | {b}{f(a['tfw'], '%.3f')}{b} | {fm} |")

print("\n## Checks\n")
print("| Variant | Reg-to-reg slack at iso (ps) | Flip-flops | Power (mW) | Annotated pins | EQUIV |")
print("|---|---|---|---|---|---|")
for v in VARIANTS:
    a = row(v)
    eq = "%d/%d" % tuple(a["equiv"]) if a["equiv"] else "–"
    print(f"| {v} | {f(a['slack'], '%+.1f')} | {a['regs'] or '–'} | {f(a['mw'], '%.2f')} | {a['pins'] or '–'} | {eq} |")

print(f"\n## Comparison at {ISO / 1e3:g} ns\n")
c = {v: row(v) for v in CMP}
print("| | SF16 SF24 t+g | SF16 SF28 t+g | FP16 FP24 (a) t+g | BF16 FP24 (a) g "
      "| SF24 vs FP16 | SF24 vs BF16 | SF28 vs FP16 | SF28 vs BF16 |")
print("|---|---|---|---|---|---|---|---|---|")
for k, lab, p, hib in (("area", "Area/MAC (µm²)", "%.0f", False), ("energy", "Energy/MAC (fJ)", "%.0f", False),
                       ("tfmm2", "TFLOPS/mm²", "%.2f", True), ("tfw", "TFLOPS/W", "%.3f", True),
                       ("fmax", "Max clock (GHz)", "%.2f", True)):
    vals = [c[v][k] for v in CMP]
    def ratio(i, j):
        if vals[i] is None or vals[j] is None:
            return "–"
        return "%.2f×" % ((vals[i] / vals[j]) if hib else (vals[j] / vals[i]))
    print(f"| {lab} | " + " | ".join(f(x, p) for x in vals) + f" | {ratio(0, 2)} | {ratio(0, 3)} | {ratio(1, 2)} | {ratio(1, 3)} |")
print("\nRatios are SF16's advantage (smaller area and energy, higher TFLOPS and clock, > 1 is SF16 ahead).")

if G2:
    print("\n## The same at 2 nm (GT2N, 500 ps; from its s2.json)\n")
    print("| | Area/MAC (µm²) | Energy/MAC (fJ) | TFLOPS/mm² | TFLOPS/W | Max clock (GHz) |")
    print("|---|---|---|---|---|---|")
    for v in CMP:
        r = G2.get(v, {})
        print(f"| {NAMES[v]} | {f(r.get('area_per_mac_um2'), '%.1f')} | {f(r.get('energy_per_mac_fj'), '%.0f')} "
              f"| {f(r.get('tflops_per_mm2_2ghz'), '%.1f')} | {f(r.get('tflops_per_w'), '%.2f')} | {f(r.get('fmax_ghz'), '%.2f')} |")
