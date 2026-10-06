#!/usr/bin/env python3
"""
GPT-2 small on four SuperFloat v1 tiles inside a HammerBlade pod, per number
format, from measured inputs only (hb/README.md):

  cycles   hb/results/<fmt>[_rb].jsonl: every launch shape the scenarios
           use, run on the HammerBlade RTL (bsg_manycore, Verilator) with the
           tiles of that format, without and with the adapter's read buffer
           (_rb); every stored output checked bit for bit. No fit: a missing
           or failed shape is an error.
  clock    the tile's own peak clock at SKY130 (hb/results/tile_signoff.json):
           on HammerBlade the chip's pin bus and top level are gone, so the
           tile alone limits it.
  power    the tile's gate-level GPT-2 power at 50 MHz, scaled with clock;
           four tiles. HammerBlade's mesh, vcaches and DRAM are not included
           (not measured).
  chip     the OpenFrame chip's cycles for the same launches
           (test/gpt2/results/<fmt>.jsonl, through its 16-bit pin bus).

Host-side work (LayerNorm, softmax, GELU, ...) is left out of both: on the
chip it was 1.6-2.0 ms per token on a laptop; on HammerBlade it would run on
the vanilla cores, which this study does not measure.

  python3 hb/bench_hb.py [--prompts 8,32,128] [--generate 32] [--json out]
"""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "test", "gpt2"))
import schedule as S                                            # noqa: E402

FORMATS = ("sf16", "fp16", "bf16")
CHIP_LAUNCH_GAP = 7       # bench.py: START low before / after a launch on the chip
POWER_CLOCK_MHZ = 50.0


def hb_cycles(cfg):
    out, bad = {}, []
    for line in open(os.path.join(HERE, "results", f"{cfg}.jsonl")):
        r = json.loads(line)
        ok = (r.get("finish") and not r.get("timeout") and r.get("mismatches") == 0
              and r.get("errors") == 0 and r.get("blocks") == r.get("nb"))
        if not ok:
            bad.append(r["name"])
            continue
        out[("gemv" if r["gemv"] else "gemm", r["kc"], r["nb"])] = r
    return out, bad


def chip_cycles(fmt):
    out = {}
    for name in (fmt, "sf16"):          # bench.py: cycles are format independent on the chip
        for line in open(os.path.join(ROOT, "test", "gpt2", "results", f"{name}.jsonl")):
            r = json.loads(line)
            if r["mismatches"] or r["host_latency"] != 0 or "check" in r["name"]:
                continue
            out.setdefault((r["kernel"], r["kc"], r["nb"]), r["cycles"])
    return out


def total(cyc, launches, gap=0):
    return sum(cyc[l] + gap for l in launches)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prompts", default="8,32,128")
    ap.add_argument("--generate", type=int, default=32)
    ap.add_argument("--json", default=os.path.join(HERE, "results", "summary.json"))
    args = ap.parse_args()
    prompts = [int(p) for p in args.prompts.split(",")]
    G = args.generate
    sig = json.load(open(os.path.join(HERE, "results", "tile_signoff.json")))["formats"]

    out = {"generate": G, "prompts": prompts, "formats": {}}
    per_fmt = {}
    cfgs = [f + v for v in ("", "_rb") for f in FORMATS
            if os.path.exists(os.path.join(HERE, "results", f"{f}{v}.jsonl"))]
    for cfg in cfgs:
        fmt = cfg.split("_")[0]
        hb, bad = hb_cycles(cfg)
        per_fmt[cfg] = hb
        hbc = {k: r["cycles"] for k, r in hb.items()}
        chip = chip_cycles(fmt)
        need = set()
        for P in prompts:
            need |= set(S.prefill(P))
            for i in range(1, G):
                need |= set(S.decode_step(P + i))
        missing = sorted(need - set(hbc))
        if missing:
            sys.exit(f"{cfg}: {len(missing)} launch shapes missing or failed on HammerBlade: {missing[:8]} (failed runs: {bad[:8]})")
        s = sig[fmt]
        f = s["tile_fmax_ss_mhz"]
        r = {"tile_fmax_ss_mhz": f, "tile_power_w_50mhz": s["tile_power_w_50mhz"],
             "tile_stdcell_area_um2": s["tile_stdcell_area_um2"], "shapes_run": len(hb), "failed_runs": bad,
             "scenarios": {}}
        for P in prompts:
            pre_l = S.prefill(P)
            dec_l = [S.decode_step(P + i) for i in range(1, G)]
            hb_pre = total(hbc, pre_l)
            hb_dec = [total(hbc, l) for l in dec_l]
            ch_pre = total(chip, pre_l, CHIP_LAUNCH_GAP)
            ch_dec = [total(chip, l, CHIP_LAUNCH_GAP) for l in dec_l]
            scale = f / POWER_CLOCK_MHZ
            p_pre = 4 * s["tile_power_w_50mhz"]["gemm"] * scale
            p_dec = 4 * s["tile_power_w_50mhz"]["gemv"] * scale
            t_pre = hb_pre / (f * 1e6)
            t_dec = [c / (f * 1e6) for c in hb_dec]
            r["scenarios"][P] = {
                "hb_prefill_cycles": hb_pre, "hb_decode_cycles": hb_dec,
                "chip_prefill_cycles": ch_pre, "chip_decode_cycles": ch_dec,
                "speedup_prefill": ch_pre / hb_pre, "speedup_decode": sum(ch_dec) / sum(hb_dec),
                "clock_mhz": f, "ttft_s": t_pre, "tpot_s": sum(t_dec) / len(t_dec),
                "e2e_s": t_pre + sum(t_dec),
                "tile_energy_j": p_pre * t_pre + p_dec * sum(t_dec),
                "tile_energy_per_decode_token_j": p_dec * sum(t_dec) / len(t_dec),
            }
        out["formats"][cfg] = r

    # cycles per shape, across formats, for each adapter
    out["format_independence"] = {}
    for v in ("", "_rb"):
        group = [f + v for f in FORMATS if f + v in per_fmt]
        if len(group) < 2:
            continue
        common = set.intersection(*(set(per_fmt[c]) for c in group))
        same = [k for k in common if len({per_fmt[c][k]["cycles"] for c in group}) == 1]
        out["format_independence"][v or "direct"] = {"formats": group, "shapes_in_all": len(common),
                                                       "identical_cycles": len(same)}
    os.makedirs(os.path.dirname(args.json), exist_ok=True)
    json.dump(out, open(args.json, "w"), indent=1)
    report(out)


def report(out):
    print(f"cycles identical across formats: {out['format_independence']}")
    for cfg, r in out["formats"].items():
        print(f"\n{cfg}: tile clock {r['tile_fmax_ss_mhz']:.1f} MHz (ss), {r['shapes_run']} shapes, failed {r['failed_runs']}")
        for P, sc in r["scenarios"].items():
            print(f"  prompt {P}: prefill {sc['hb_prefill_cycles'] / 1e6:.1f} M cycles (chip {sc['chip_prefill_cycles'] / 1e6:.1f} M, "
                  f"{sc['speedup_prefill']:.2f}x), decode/token {sum(sc['hb_decode_cycles']) / len(sc['hb_decode_cycles']) / 1e6:.1f} M "
                  f"({sc['speedup_decode']:.2f}x), TTFT {sc['ttft_s']:.1f} s, TPOT {sc['tpot_s']:.2f} s, "
                  f"tiles {sc['tile_energy_j']:.1f} J")


if __name__ == "__main__":
    main()
