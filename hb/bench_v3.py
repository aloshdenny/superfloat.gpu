#!/usr/bin/env python3
"""
GPT-2 small prefill (time to first token) on four SuperFloat v3 matrix tiles
in a HammerBlade pod, per number format, from measured inputs:

  cycles  hb/results/<machine>_<cfg>.jsonl: every matrix multiply shape of a
          T-token prefill, run on the HammerBlade RTL with that format's
          tiles, every result checked bit for bit (sw/v3/main.c). Per layer:
          qkv, proj, fc1, fc2 once and 12 x (scores + av); 12 layers; then
          the LM head for the last token. The LM head is run on 2,048 and
          4,096 of its 50,257 columns and extended along the line through
          those two points (its cycles grow with the number of 8-column
          blocks): the only extrapolated term.
  clock   each format's array (v3/pe, its 8 x 8 wavefront block at GT2N)
          peak clock, from hb/results/v3_clock.json. The time assumes the whole pod runs at
          that clock; at any common clock the formats' times are in the ratio
          of their cycles.

Matrix multiplies only: LayerNorm, softmax, GELU and the rest are not
counted (the v1 study did the same).

  python3 hb/bench_v3.py [--json out]
"""
import argparse
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
LAYERS, HEADS, VOCAB = 12, 12, 50257
TS = (8, 32, 128)


def runs(cfg):
    out, bad = {}, []
    p = os.path.join(HERE, "results", f"{cfg}.jsonl")
    if not os.path.exists(p):
        return None, None
    for line in open(p):
        r = json.loads(line)
        ok = r.get("finish") and not r.get("timeout") and r.get("mismatches") == 0 and r.get("errors") == 0
        if ok:
            out[r["name"]] = r
        else:
            bad.append(r["name"])
    return out, bad


def prefill(cyc, T):
    layer = cyc[f"qkv_t{T}"] + cyc[f"proj_t{T}"] + cyc[f"fc1_t{T}"] + cyc[f"fc2_t{T}"] \
        + HEADS * (cyc[f"scores_t{T}"] + cyc[f"av_t{T}"])
    a, b = cyc["lmhead_c2048"], cyc["lmhead_c4096"]
    lm = a + (b - a) * (VOCAB - 2048) / 2048
    return LAYERS * layer + lm, LAYERS * layer, lm


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", default=os.path.join(HERE, "results", "v3_summary.json"))
    args = ap.parse_args()
    clk_path = os.path.join(HERE, "results", "v3_clock.json")
    clock = json.load(open(clk_path)) if os.path.exists(clk_path) else {}
    out = {"prompts": TS, "configs": {}}
    # v3_<fmt>: 8 x 8, one product stage, no hashing; v3i_<fmt>_m2: IPOLY
    # hashing, two product stages (the GT2N-measured array); _m2a4: 4 x 4
    cfgs = [f"{m}_{f}{s}" for m, s in (("v3", ""), ("v3i", "_m2"), ("v3i", "_m2a4")) for f in ("sf16", "fp16", "bf16")]
    for cfg in cfgs:
        rs, bad = runs(cfg)
        if rs is None:
            continue
        cyc = {k: r["cycles"] for k, r in rs.items()}
        fmt = cfg.split("_")[1]
        ghz = clock.get(fmt, {}).get("fmax_ghz")
        c = {"failed": bad, "launches": len(rs), "fmax_ghz": ghz, "prompts": {}}
        for T in TS:
            try:
                total, layers, lm = prefill(cyc, T)
            except KeyError as e:
                c["prompts"][T] = {"missing": str(e)}
                continue
            c["prompts"][T] = {"cycles": total, "layers_cycles": layers, "lmhead_cycles": lm,
                               "ttft_ms": total / (ghz * 1e9) * 1e3 if ghz else None}
        out["configs"][cfg] = c
    json.dump(out, open(args.json, "w"), indent=1)
    for cfg, c in out["configs"].items():
        print(f"{cfg}: {c['launches']} launches, failed {c['failed']}, fmax {c['fmax_ghz']} GHz")
        for T, p in c["prompts"].items():
            if "missing" in p:
                print(f"  T={T}: missing {p['missing']}")
                continue
            t = f", TTFT {p['ttft_ms']:.3f} ms" if p["ttft_ms"] else ""
            print(f"  T={T}: {p['cycles'] / 1e6:.2f} M cycles (layers {p['layers_cycles'] / 1e6:.2f} M, "
                  f"LM head {p['lmhead_cycles'] / 1e6:.2f} M){t}")


if __name__ == "__main__":
    main()
