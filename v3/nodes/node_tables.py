#!/usr/bin/env python3
"""Markdown tables for a node's write-up from ../nodes/<node>/s2.json (made
by ../pe/collect_s2.py <node> <period>), with the 2 nm figures alongside
(../pe/results/s2.json if present, else a path given as the third argument).

  node_tables.py <node> <iso_period_ps> [gt2n s2.json]

Per variant, at a clock period T (from that period's run):
  area/MAC    standard-cell area / 64           energy/MAC  P x T / 64
  TFLOPS/mm2  2 FLOPs / T / area per MAC        TFLOPS/W    2 FLOPs / energy per MAC
  max clock   1 / (300 ps - reg-to-reg slack), from the 300 ps run
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "pe"))
from variants import VARIANTS, latency          # noqa: E402

node, iso = sys.argv[1], int(sys.argv[2])
d = json.load(open(os.path.join(HERE, node, "s2.json")))["variants"]
g2p = sys.argv[3] if len(sys.argv) > 3 else os.path.join(HERE, "..", "pe", "results", "s2.json")
g2 = json.load(open(g2p)) if os.path.exists(g2p) else {}

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
CMP = [("sf16_sf24_tg", "SF16 SF24 t+g"), ("sf16_sf28_tg", "SF16 SF28 t+g"),
       ("fp16_fp24_a_tg", "FP16 FP24 (a) t+g"), ("bf16_fp24_a_g", "BF16 FP24 (a) g")]


def at(r, ps, node=node):
    """area/MAC, energy/MAC, TFLOPS/mm2, TFLOPS/W, meets, at period ps."""
    t = r.get(node, {}).get(str(ps), {})
    out = {}
    if "area_um2" in t:
        out["area"] = t["area_um2"] / 64
        out["tfmm2"] = 2 * (1e12 / ps) / (out["area"] * 1e-6) / 1e12
    if "total" in t:
        out["energy"] = t["total"]["total"] * (ps / 1e12) / 64 * 1e15
        out["tfw"] = 2 / (out["energy"] * 1e-15) / 1e12
    if "r2r_slack_ps" in t:
        out["meets"] = t["r2r_slack_ps"] >= 0
        out["slack"] = t["r2r_slack_ps"]
    if "equiv" in t:
        out["equiv"] = t["equiv"]
    if "annotated_pins" in t:
        out["pins"] = t["annotated_pins"]
    return out


def fmt(x, f):
    return (f % x) if x is not None else "–"


def table(ps, title):
    print(f"\n{title}\n")
    print("| Variant | Stages | Meets | Area/MAC (µm²) | Energy/MAC (fJ) | TFLOPS/mm² | TFLOPS/W | Max clock (GHz) |")
    print("|---|---|---|---|---|---|---|---|")
    for v in VARIANTS:
        r = d.get(v, {})
        a = at(r, ps)
        print(f"| {NAMES[v]} | {latency(VARIANTS[v])} | {'yes' if a.get('meets') else 'no' if 'meets' in a else '–'} "
              f"| {fmt(a.get('area'), '%.1f')} | {fmt(a.get('energy'), '%.0f')} | {fmt(a.get('tfmm2'), '%.1f')} "
              f"| {fmt(a.get('tfw'), '%.2f')} | {fmt(r.get('fmax_ghz'), '%.2f')} |")


table(iso, f"## All variants at {iso} ps ({1e3 / iso:.2f} GHz)")
table(500, "## All variants at 500 ps (2 GHz, the 2 nm clock)")

print(f"\n## Comparison at {iso} ps\n")
print("| | " + " | ".join(n for _, n in CMP) + " |")
print("|---|" + "---|" * len(CMP))
rows = [("Area/MAC (µm²)", "area", "%.1f"), ("Energy/MAC (fJ)", "energy", "%.0f"),
        ("TFLOPS/mm²", "tfmm2", "%.1f"), ("TFLOPS/W", "tfw", "%.2f")]
A = {v: at(d[v], iso) for v, _ in CMP}
for lab, k, f in rows:
    print(f"| {lab} | " + " | ".join(fmt(A[v].get(k), f) for v, _ in CMP) + " |")
print("| Max clock (GHz) | " + " | ".join(fmt(d[v].get("fmax_ghz"), "%.2f") for v, _ in CMP) + " |")
print(f"| Meets {iso} ps (slack, ps) | " + " | ".join(
    f"{'yes' if A[v].get('meets') else 'no'} ({A[v].get('slack', 0):+.1f})" for v, _ in CMP) + " |")

print(f"\n## Ratios at {iso} ps (SF16 ahead by)\n")
print("| | SF24 vs FP16 | SF24 vs BF16 | SF28 vs FP16 | SF28 vs BF16 |")
print("|---|---|---|---|---|")
s24, s28, f16, b16 = (A[v] for v, _ in CMP)
F = {v: d[v].get("fmax_ghz") for v, _ in CMP}
for lab, k, inv in [("Area/MAC", "area", True), ("Energy/MAC", "energy", True),
                    ("TFLOPS/mm²", "tfmm2", False), ("TFLOPS/W", "tfw", False)]:
    def ratio(s, o):
        return (o[k] / s[k]) if inv else (s[k] / o[k])
    print(f"| {lab} | {ratio(s24, f16):.2f}× | {ratio(s24, b16):.2f}× | {ratio(s28, f16):.2f}× | {ratio(s28, b16):.2f}× |")
print(f"| Max clock | {F['sf16_sf24_tg'] / F['fp16_fp24_a_tg']:.2f}× | {F['sf16_sf24_tg'] / F['bf16_fp24_a_g']:.2f}× "
      f"| {F['sf16_sf28_tg'] / F['fp16_fp24_a_tg']:.2f}× | {F['sf16_sf28_tg'] / F['bf16_fp24_a_g']:.2f}× |")

if g2:
    print("\n## 2 nm (GT2N, 500 ps) alongside\n")
    print("| | " + " | ".join(n for _, n in CMP) + " |")
    print("|---|" + "---|" * len(CMP))
    G = {v: at(g2[v], 500, "gt2n") for v, _ in CMP}
    for lab, k, f in rows:
        print(f"| {lab} | " + " | ".join(fmt(G[v].get(k), f) for v, _ in CMP) + " |")
    print("| Max clock (GHz) | " + " | ".join(fmt(g2[v].get("fmax_ghz"), "%.2f") for v, _ in CMP) + " |")

print("\n## Checks\n")
for ps in (iso, 500):
    eq = [(v, at(d[v], ps).get("equiv"), at(d[v], ps).get("pins")) for v in VARIANTS]
    ok = sum(1 for _, e, _ in eq if e and e[0] == e[1])
    pins = [p for _, _, p in eq if p]
    print(f"- {ps} ps: EQUIV a = b in {ok}/{len(eq)} variants; annotated pins "
          f"{min(pins) if pins else 0:,}–{max(pins) if pins else 0:,}; "
          f"failures: {[v for v, e, _ in eq if not (e and e[0] == e[1])]}")
