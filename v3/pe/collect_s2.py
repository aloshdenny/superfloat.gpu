#!/usr/bin/env python3
"""
Collect study S2's measurements: GT2N reports from the pod (report.sh,
gl_power.sh) and SKY130 synthesis areas from the build server
(sky130_synth.sh). Writes results/s2.json and prints a table.

Per 8 x 8 block (64 MACs, edge registers included):
  area/MAC      standard-cell area / 64
  energy/MAC    total power on the GPT-2 stimulus x clock period / 64
  fmax          register to register: 1 / (T - slack) from the 300 ps run
"""
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from variants import VARIANTS                               # noqa: E402

POD = ["ssh", "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null", "-o", "LogLevel=ERROR",
       "-p", os.environ.get("POD_PORT", "40361"), "root@" + os.environ.get("POD_IP", "213.173.111.79")]
SRV = os.path.expanduser("/Users/aoxo/vscode/superfloat.gpu-v2/build/tools/srv.sh")


def pod_cat(path):
    r = subprocess.run(POD + [f"cat {path} 2>/dev/null"], capture_output=True, text=True)
    return r.stdout


def parse_timing(t):
    out = {}
    m = re.search(r"Design area ([\d.]+) um\^2 ([\d.]+)% utilization", t)
    if m:
        out["area_um2"], out["util_pct"] = float(m.group(1)), float(m.group(2))
    m = re.search(r"CELLS (\d+) REGS (\d+)", t)
    if m:
        out["cells"], out["regs"] = int(m.group(1)), int(m.group(2))
    m = re.search(r"REG2REG.*?\s(-?[\d.]+) \((MET|VIOLATED)\)", t, re.S)
    if m:
        out["r2r_slack_ps"] = float(m.group(1))
    m = re.search(r"worst slack max (-?[\d.]+)", t)
    if m:
        out["worst_slack_ps"] = float(m.group(1))
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
    sky = subprocess.run([SRV], input="cat ~/alosh/v3_s2/sky130.log\n", capture_output=True, text=True).stdout
    for name in VARIANTS:
        r = {"gt2n": {}}
        m = re.search(rf"^{name} area ([\d.]+) cells \S* flops (\d+)", sky, re.M)
        if m:
            r["sky130"] = {"area_um2": float(m.group(1)), "flops": int(m.group(2)),
                           "area_per_mac_um2": float(m.group(1)) / 64}
        for ps in (500, 300):
            t = parse_timing(pod_cat(f"/root/v3/reports/{name}_{ps}.txt"))
            if ps == 500:
                t.update(parse_power(pod_cat(f"/root/v3/reports/{name}_{ps}_power.txt")))
            r["gt2n"][str(ps)] = t
        g5, g3 = r["gt2n"]["500"], r["gt2n"]["300"]
        if "area_um2" in g5:
            r["area_per_mac_um2"] = g5["area_um2"] / 64
        if "total" in g5:
            r["power_mw_2ghz"] = g5["total"]["total"] * 1e3
            r["energy_per_mac_fj"] = g5["total"]["total"] * 500e-12 / 64 * 1e15
        if "r2r_slack_ps" in g3:
            r["fmax_ghz"] = 1e3 / (300 - min(g3["r2r_slack_ps"], 0.0))
            r["fmax_capped"] = g3["r2r_slack_ps"] >= 0
        if "r2r_slack_ps" in g5:
            r["meets_2ghz"] = g5["r2r_slack_ps"] >= 0
        res[name] = r
    os.makedirs(os.path.join(HERE, "results"), exist_ok=True)
    json.dump(res, open(os.path.join(HERE, "results", "s2.json"), "w"), indent=1)
    print(f"{'variant':14s} {'2GHz':>5s} {'um2/MAC':>8s} {'fJ/MAC':>7s} {'mW':>6s} {'fmax':>6s} {'regs':>6s} {'sky130':>8s} equiv")
    for n, r in res.items():
        f = lambda k, fmt: (fmt % r[k]) if k in r else "-"
        eq = r["gt2n"]["500"].get("equiv")
        print(f"{n:14s} {str(r.get('meets_2ghz', '-')):>5s} {f('area_per_mac_um2', '%8.2f')} "
              f"{f('energy_per_mac_fj', '%7.1f')} {f('power_mw_2ghz', '%6.1f')} {f('fmax_ghz', '%6.2f')} "
              f"{r['gt2n']['500'].get('regs', '-'):>6} "
              f"{('%8.0f' % r['sky130']['area_per_mac_um2']) if 'sky130' in r else '-':>8s} "
              f"{'%d/%d' % tuple(eq) if eq else '-'}")


if __name__ == "__main__":
    main()
