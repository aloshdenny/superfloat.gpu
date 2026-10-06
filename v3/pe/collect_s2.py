#!/usr/bin/env python3
"""
Collect study S2's measurements from local copies of the pods' reports
(results/<node>*/reports: report.sh, gl_power.sh) and the build server's
SKY130 synthesis log (results/sky130_synth.log), and print a table.

  collect_s2.py [node [iso_ps [max_ps]]]
node gt2n (default: 500 and 300 ps) writes results/s2.json as before; any
other node writes ../nodes/<node>/s2.json. iso_ps is the run that gives area,
power and the TFLOPS figures; max_ps the run that gives fmax. Report files
are named in ps on every node; slacks are read in the report's TIME_UNIT
(ns on nangate45) and stored in ps.

Per 8 x 8 block (64 MACs, edge registers included):
  area/MAC      standard-cell area / 64
  energy/MAC    total power on the GPT-2 stimulus x clock period / 64
  fmax          register to register: 1 / (T_max - slack) from the max_ps run
  TFLOPS/mm2    2 FLOPs per MAC per cycle at 1 / iso_ps / area per MAC
  TFLOPS/W      2 FLOPs per MAC / energy per MAC
"""
import json
import os
import re
import glob
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from variants import VARIANTS                               # noqa: E402

RES = os.path.join(HERE, "results")
NODE = sys.argv[1] if len(sys.argv) > 1 else "gt2n"
ISO = int(sys.argv[2]) if len(sys.argv) > 2 else 500
MAXP = int(sys.argv[3]) if len(sys.argv) > 3 else 300
SFX = "2ghz" if ISO == 500 else f"{ISO}ps"


def report(name):
    """A report file from the newest results/<node>*/reports that has it."""
    for d in sorted(glob.glob(os.path.join(RES, NODE + "*", "reports")), reverse=True):
        p = os.path.join(d, name)
        if os.path.exists(p):
            return open(p).read()
    return ""


def parse_timing(t):
    out = {}
    m = re.search(r"^TIME_UNIT (\w+)", t, re.M)
    k = {"ps": 1.0, "ns": 1000.0}[m.group(1)] if m else 1.0
    m = re.search(r"Design area ([\d.]+) um\^2 ([\d.]+)% utilization", t)
    if m:
        out["area_um2"], out["util_pct"] = float(m.group(1)), float(m.group(2))
    m = re.search(r"CELLS (\d+) REGS (\d+)", t)
    if m:
        out["cells"], out["regs"] = int(m.group(1)), int(m.group(2))
    m = re.search(r"REG2REG.*?\s(-?[\d.]+) \((MET|VIOLATED)\)", t, re.S)
    if m:
        out["r2r_slack_ps"] = float(m.group(1)) * k
    m = re.search(r"worst slack max (-?[\d.]+)", t)
    if m:
        out["worst_slack_ps"] = float(m.group(1)) * k
    return out


def parse_power(t):
    out = {}
    for g in ("Sequential", "Combinational", "Clock", "Total"):
        m = re.search(rf"^{g}\s+([\d.e+-]+)\s+([\d.e+-]+)\s+([\d.e+-]+)\s+([\d.e+-]+)", t, re.M)
        if m:
            out[g.lower()] = dict(zip(("internal", "switching", "leakage", "total"), map(float, m.groups())))
    m = re.search(r"Annotated (\d+) pin activities", t)
    if m:
        out["annotated_pins"] = int(m.group(1))
    m = re.search(r"EQUIV (\d+)/(\d+)", t)
    if m:
        out["equiv"] = [int(m.group(1)), int(m.group(2))]
    return out


def main():
    res = {}
    p = os.path.join(RES, "sky130_synth.log")
    sky = open(p).read() if os.path.exists(p) else ""
    for name in VARIANTS:
        r = {NODE: {}}
        m = re.search(rf"^{name} area ([\d.]+) cells \S* flops (\d+)", sky, re.M)
        if m:
            r["sky130"] = {"area_um2": float(m.group(1)), "flops": int(m.group(2)),
                           "area_per_mac_um2": float(m.group(1)) / 64}
        for ps in (ISO, MAXP):
            t = parse_timing(report(f"{name}_{ps}.txt"))
            if ps == ISO:
                t.update(parse_power(report(f"{name}_{ps}_power.txt")))
            r[NODE][str(ps)] = t
        g5, g3 = r[NODE][str(ISO)], r[NODE][str(MAXP)]
        if "area_um2" in g5:
            r["area_per_mac_um2"] = g5["area_um2"] / 64
            r[f"tflops_per_mm2_{SFX}"] = 2 * (1e12 / ISO) / (r["area_per_mac_um2"] * 1e-6) / 1e12
        if "total" in g5:
            r[f"power_mw_{SFX}"] = g5["total"]["total"] * 1e3
            r["energy_per_mac_fj"] = g5["total"]["total"] * (ISO * 1e-12) / 64 * 1e15
            r["tflops_per_w"] = 2 / (r["energy_per_mac_fj"] * 1e-15) / 1e12
        if "r2r_slack_ps" in g3:
            r["fmax_ghz"] = 1e3 / (MAXP - min(g3["r2r_slack_ps"], 0.0))   # capped at 1 / T_max if met
            r["fmax_capped"] = g3["r2r_slack_ps"] >= 0
        if "r2r_slack_ps" in g5:
            r[f"meets_{SFX}"] = g5["r2r_slack_ps"] >= 0
        res[name] = r
    if NODE == "gt2n":
        out = os.path.join(HERE, "results", "s2.json")
        json.dump(res, open(out, "w"), indent=1)
    else:
        out = os.path.join(HERE, "..", "nodes", NODE, "s2.json")
        os.makedirs(os.path.dirname(out), exist_ok=True)
        json.dump({"node": NODE, "iso_period_ps": ISO, "max_period_ps": MAXP, "variants": res},
                  open(out, "w"), indent=1)
    print(f"{NODE}: area, power, TFLOPS at {ISO} ps; fmax from {MAXP} ps -> {os.path.relpath(out, HERE)}")
    print(f"{'variant':15s} {'meets':>5s} {'um2/MAC':>8s} {'fJ/MAC':>7s} {'TF/mm2':>7s} {'TF/W':>6s} {'fmax':>6s} {'regs':>6s} {'sky130':>8s} equiv")
    for n, r in res.items():
        f = lambda k, fmt: (fmt % r[k]) if k in r else "-"
        eq = r[NODE][str(ISO)].get("equiv")
        print(f"{n:15s} {str(r.get(f'meets_{SFX}', '-')):>5s} {f('area_per_mac_um2', '%8.2f')} "
              f"{f('energy_per_mac_fj', '%7.1f')} {f(f'tflops_per_mm2_{SFX}', '%7.1f')} {f('tflops_per_w', '%6.2f')} {f('fmax_ghz', '%6.2f')} "
              f"{r[NODE][str(ISO)].get('regs', '-'):>6} "
              f"{('%8.0f' % r['sky130']['area_per_mac_um2']) if 'sky130' in r else '-':>8s} "
              f"{'%d/%d' % tuple(eq) if eq else '-'}")


if __name__ == "__main__":
    main()
