#!/usr/bin/env python3
"""
GPT-2 small on the three signed-off OpenFrame chips: latency, cycles, clock
and energy, from measured inputs only (docs/gpt2_benchmark.md):

  cycles   results/<fmt>.jsonl: launches simulated through the chip's pins
           (test_gpt2_bench.py). Shapes not simulated exactly come from a
           per-kernel fit cycles = a + b * bus beats over the simulated ones;
           its worst residual is printed.
  clock    peak clock = 1 / (20 ns - worst setup slack) over the chip and its
           tile, from the signoff metrics (signoff/<fmt>/{chip,tile}).
  power    power/<fmt>_<kernel>.json: OpenSTA on gate-level activity of the
           signed-off netlists (power/run_power.sh), at 50 MHz.
  host     LayerNorm, softmax, GELU, bias and residual adds, embedding and
           argmax in numpy on this machine (gpt2.py), timed per step.

  python3 bench.py [--prompts 8,32,128] [--generate 32] [--json out.json]
"""
import argparse
import json
import os
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import schedule as S                                            # noqa: E402

FORMATS = ("sf16", "fp16", "bf16")
SIGNOFF = os.path.join(os.path.dirname(os.path.dirname(HERE)), "signoff")
LAUNCH_GAP = 7            # START low before / after a launch (test_gpt2_bench.run_launch)
SIGNOFF_PERIOD_NS = 20.0
POWER_CLOCK_MHZ = 50.0


# ---------------------------------------------------------------- cycles

def beats(kernel, kc, nb, program_reads):
    if kernel == "gemv":
        reads, writes = nb * (kc // 8 * 72 + 24), nb * 8
    else:
        reads, writes = nb * (kc * 16 + 24), nb * 64
    return reads + program_reads + 2 * writes


class Cycles:
    """Cycles of a launch: measured if simulated, else the per-kernel fit."""

    def __init__(self, fmt):
        self.meas = {}
        prog = {}
        for line in open(os.path.join(HERE, "results", f"{fmt}.jsonl")):
            r = json.loads(line)
            if r["mismatches"] or r["host_latency"] != 0:
                continue
            key = (r["kernel"], r["kc"], r["nb"])
            self.meas[key] = r["cycles"]
            prog.setdefault(r["kernel"], []).append(r["program_reads"])
            b = r["data_reads"] + r["program_reads"] + 2 * r["writes"]
            assert b == beats(r["kernel"], r["kc"], r["nb"], r["program_reads"]), (r, b)
        self.prog = {k: float(np.mean(v)) for k, v in prog.items()}
        self.fit, self.resid = {}, {}
        for kernel in ("gemv", "gemm"):
            pts = [(beats(k, kc, nb, self.prog[k]), c) for (k, kc, nb), c in self.meas.items() if k == kernel]
            x, y = np.array([p[0] for p in pts]), np.array([p[1] for p in pts])
            A = np.vstack([np.ones_like(x), x]).T
            a, b = np.linalg.lstsq(A, y, rcond=None)[0]
            self.fit[kernel] = (a, b)
            self.resid[kernel] = float(np.max(np.abs((a + b * x) - y) / y)) if len(y) else 0.0
        self.used_fit = 0

    def __call__(self, kernel, kc, nb):
        key = (kernel, kc, nb)
        if key in self.meas:
            return self.meas[key]
        self.used_fit += 1
        a, b = self.fit[kernel]
        return a + b * beats(kernel, kc, nb, self.prog[kernel])

    def total(self, launches):
        return sum(self(*l) + LAUNCH_GAP for l in launches)


# ---------------------------------------------------------------- clock

def peak_clock(fmt, corner):
    ws = []
    for blk in ("chip", "tile"):
        m = json.load(open(os.path.join(SIGNOFF, fmt, blk, "final", "metrics.json")))
        ws.append(m[f"timing__setup__ws__corner:{corner}"])
    return 1e3 / (SIGNOFF_PERIOD_NS - min(ws)), ("tile" if ws[1] < ws[0] else "chip")


# ---------------------------------------------------------------- power

def power(fmt, kernel):
    """Chip power in W at 50 MHz: top level + 4 tiles, from gate-level activity."""
    p = json.load(open(os.path.join(HERE, "power", "results", f"{fmt}_{kernel}.json")))
    return p["top_w"] + 4 * p["tile_w"], p


# ---------------------------------------------------------------- host

def host_times(prompt, generate):
    """Host-op seconds for the prefill and for each decode step."""
    from gpt2 import GPT2, HostTimer, new_cache, tokenizer
    model = GPT2()
    tok = tokenizer()
    ids = (tok.encode("The OpenFrame chip runs GPT-2 one layer at a time. ").ids * 64)[:prompt]
    cache = new_cache()
    tm = HostTimer()
    _, nxt = model.forward(ids, cache, tm)
    pre = sum(tm.t.values())
    steps = []
    for _ in range(generate - 1):
        tm = HostTimer()
        _, nxt = model.forward([nxt], cache, tm)
        steps.append(sum(tm.t.values()))
    return pre, steps


# ---------------------------------------------------------------- report

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prompts", default="8,32,128")
    ap.add_argument("--generate", type=int, default=32)
    ap.add_argument("--json", default=os.path.join(HERE, "results", "summary.json"))
    args = ap.parse_args()
    prompts = [int(p) for p in args.prompts.split(",")]
    G = args.generate

    host = {P: host_times(P, G) for P in prompts}
    out = {"generate": G, "prompts": prompts, "formats": {}}
    for fmt in FORMATS:
        cyc = Cycles(fmt)
        f_ss, lim_ss = peak_clock(fmt, "max_ss_100C_1v60")
        f_tt, lim_tt = peak_clock(fmt, "nom_tt_025C_1v80")
        p_dec, pd = power(fmt, "gemv")
        p_pre, pp = power(fmt, "gemm")
        r = {"fit_resid": cyc.resid, "fit_launches": 0,
             "fmax_ss_mhz": f_ss, "fmax_ss_limit": lim_ss, "fmax_tt_mhz": f_tt, "fmax_tt_limit": lim_tt,
             "power_decode_w": p_dec, "power_prefill_w": p_pre, "power_detail": {"gemv": pd, "gemm": pp},
             "scenarios": {}}
        for P in prompts:
            pre_l = S.prefill(P)
            pre_c = cyc.total(pre_l)
            dec_c = [cyc.total(S.decode_step(P + i)) for i in range(1, G)]
            hp, hs = host[P]
            sc = {"prefill_launches": len(pre_l), "prefill_cycles": pre_c,
                  "decode_launches": len(S.decode_step(P + 1)), "decode_cycles": dec_c,
                  "host_prefill_s": hp, "host_decode_s": hs}
            for tag, f in (("ss", f_ss), ("50", POWER_CLOCK_MHZ)):
                t_pre = pre_c / (f * 1e6)
                t_dec = [c / (f * 1e6) for c in dec_c]
                scale = f / POWER_CLOCK_MHZ                     # dynamic power scales with clock
                e_pre = p_pre * scale * t_pre
                e_dec = [p_dec * scale * t for t in t_dec]
                sc[tag] = {"clock_mhz": f, "prefill_s": t_pre, "ttft_s": t_pre + hp,
                           "tpot_s": [t + h for t, h in zip(t_dec, hs)],
                           "e2e_s": t_pre + hp + sum(t_dec) + sum(hs),
                           "energy_prefill_j": e_pre, "energy_decode_j": e_dec,
                           "energy_total_j": e_pre + sum(e_dec)}
            r["scenarios"][P] = sc
        r["fit_launches"] = cyc.used_fit
        out["formats"][fmt] = r
    os.makedirs(os.path.dirname(args.json), exist_ok=True)
    json.dump(out, open(args.json, "w"), indent=1)
    report(out)


def report(out):
    G = out["generate"]
    for fmt, r in out["formats"].items():
        print(f"\n{fmt}: peak clock {r['fmax_ss_mhz']:.1f} MHz (ss, {r['fmax_ss_limit']}), "
              f"{r['fmax_tt_mhz']:.1f} MHz (tt, {r['fmax_tt_limit']}); power decode {r['power_decode_w'] * 1e3:.1f} mW, "
              f"prefill {r['power_prefill_w'] * 1e3:.1f} mW at 50 MHz; fit residual {r['fit_resid']}, "
              f"{r['fit_launches']} launch lookups from the fit")
        for P, sc in r["scenarios"].items():
            s = sc["ss"]
            print(f"  prompt {P}: prefill {sc['prefill_cycles'] / 1e6:.1f} M cycles, TTFT {s['ttft_s']:.1f} s, "
                  f"TPOT {np.mean(s['tpot_s']):.2f} s, {G} tokens end to end {s['e2e_s']:.0f} s, "
                  f"energy {s['energy_total_j']:.2f} J")


if __name__ == "__main__":
    main()
