#!/usr/bin/env python3
"""
v3 at 2 nm: a near-reticle die with the measured GT2N PE numbers (study S2
and the levers, docs/v3_gt2n.md), the same on-die SRAM in every format, and
large GPT-2 and YOLOv8 workloads. A roofline over five limits per workload:

  mxu     matrix-unit cycles: every GEMM tiled into 128 x 128 weight tiles,
          max(M, 128) cycles per tile (a tile's 128 weight rows load while
          the previous computes), plus the fill latency 128 * L + 128 per GEMM
  vector  the vector units: every non-matmul op lowered to SF16/FP ops
  hbm     off-die bytes (what does not fit the SRAM, and the inputs) / HBM BW
  power   (MAC energy + HBM energy) / the power cap
  latency at batch 1 the MXU and vector work of a step are sequential

Measured (GT2N, 8 x 8 blocks, every lever): area and energy per MAC, max
clock, partial-sum stages per PE (L). Modeled, the same in every format:
die and region areas, SRAM density (published N2 macro), HBM, vector
units, power cap, idle-array energy. See CHIP below.

  python3 v3_perf.py [out.json]
"""
import json
import math
import sys

# ---------------------------------------------------------------- formats
# GT2N, 2 GHz, GPT-2 power stimulus; perplexity from study S1.
FMT = {
    "sf16": dict(name="SF16, SF24 accumulator, truncated + gated", area_um2=66.52, e_fj=232.67,
                 fmax=2.62, L=1, ppl_pct=0.55, scale_ops=2),
    "fp16": dict(name="FP16, FP24 accumulator (a), truncated + gated", area_um2=113.00, e_fj=588.69,
                 fmax=2.82, L=3, ppl_pct=0.02, scale_ops=0),
    "bf16": dict(name="BF16, FP24 accumulator (a), gated", area_um2=98.20, e_fj=486.59,
                 fmax=2.87, L=3, ppl_pct=0.72, scale_ops=0),
}

# ------------------------------------------------------------------- chip
CHIP = dict(
    clock_ghz=2.0,             # every format meets 2 GHz (S2)
    die_mm2=800.0,             # near the 858 mm2 reticle
    array_mm2=70.0,            # matrix units, the same area in every format
    core_mm2=14.0,             # vector units, scalar cores, DMA, NoC (modeled: 20% of the arrays)
    io_mm2=40.0,               # HBM PHYs, PLLs, host link (modeled)
    sram_mb_per_mm2=38.1 / 8,  # published N2 SRAM macro density, 38.1 Mb/mm2
    vpus=16, vpu_lanes=128,    # 16 vector units of 128 lanes, one op per lane per cycle
    hbm_tbs=4.8, hbm_gb=144,   # 4 HBM3E stacks: 1.2 TB/s and 36 GB each
    hbm_pj_bit=3.97,           # NVIDIA, MICRO 2017
    power_w=700.0,             # H100 SXM's TDP
    idle_frac=0.3,             # an allocated array's energy per cycle without data, vs full (modeled)
    wload_rows=1,              # weight rows a matrix unit loads per cycle (the shift chain: 1)
)
TILE = 128
# Where the bottleneck moves, the same in every format:
SCEN = {
    "planned": {},                                       # the plan's vector units
    "wide_vpu": {"vpu_lanes": 4096},                     # 65,536 lanes, 1/16 of SF16's MACs
    "wide_vpu_wload4": {"vpu_lanes": 4096, "wload_rows": 4},
}
S = {}                                                   # the scenario being run


def chip(fmt):
    f = FMT[fmt]
    c = dict(CHIP, **S)
    c["mxus"] = int(CHIP["array_mm2"] * 1e6 // (TILE * TILE * f["area_um2"]))
    c["macs"] = c["mxus"] * TILE * TILE
    c["sram_mb"] = (CHIP["die_mm2"] - CHIP["array_mm2"] - CHIP["core_mm2"] - CHIP["io_mm2"]) * CHIP["sram_mb_per_mm2"]
    c["peak_tflops"] = c["macs"] * 2 * CHIP["clock_ghz"] * 1e9 / 1e12
    c["peak_w"] = c["macs"] * f["e_fj"] * 1e-15 * CHIP["clock_ghz"] * 1e9
    c["tflops_per_w"] = 2 / (f["e_fj"] * 1e-15) / 1e12
    c["tflops_per_mm2_array"] = 2 * CHIP["clock_ghz"] * 1e9 / (f["area_um2"] * 1e-6) / 1e12
    c["vec_tops"] = CHIP["vpus"] * CHIP["vpu_lanes"] * CHIP["clock_ghz"] * 1e9 / 1e12
    return c


# ------------------------------------------------------------------ costs
class Cost:
    """Accumulates one workload's MXU cycles, MACs, array occupancy, vector
    ops and off-die bytes."""

    def __init__(self, fmt):
        self.f, self.c = FMT[fmt], chip(fmt)
        self.cyc = 0.0          # MXU cycles, GEMMs one after another
        self.macs = 0.0         # useful MACs
        self.occ = 0.0          # MAC-cycles of allocated arrays
        self.vops = 0.0         # vector ops
        self.hbm = 0.0          # off-die bytes

    def gemm(self, M, K, N, count=1, frac=1.0):
        """count independent (M x K) @ (K x N) GEMMs; frac < 1 skips tiles
        (causal attention)."""
        if M <= 0 or count <= 0:
            return
        n = self.c["mxus"]
        tiles = math.ceil(K / TILE) * math.ceil(N / TILE) * count * frac
        if tiles >= n:
            rounds, m_eff = math.ceil(tiles / n), M
            busy = tiles
        else:
            r = max(1, n // max(1, math.ceil(tiles)))
            m_eff = math.ceil(M / r)
            rounds, busy = 1, min(n, math.ceil(tiles) * r)
        per_tile = max(m_eff, TILE // self.c["wload_rows"])
        self.cyc += rounds * per_tile + TILE * self.f["L"] + TILE + 1
        self.macs += M * K * N * count * frac
        self.occ += busy * per_tile * TILE * TILE

    def vec(self, ops):
        self.vops += ops

    def result(self, batch1=False, units=1.0):
        c, f = self.c, self.f
        hz = c["clock_ghz"] * 1e9
        t_mxu = self.cyc / hz
        t_vec = self.vops / (c["vpus"] * c["vpu_lanes"] * hz)
        t_hbm = self.hbm / (c["hbm_tbs"] * 1e12)
        e_mac = (self.macs + c["idle_frac"] * max(0.0, self.occ - self.macs)) * f["e_fj"] * 1e-15
        e_hbm = self.hbm * 8 * c["hbm_pj_bit"] * 1e-12
        t_pow = (e_mac + e_hbm) / c["power_w"]
        limits = {"mxu": t_mxu, "vector": t_vec, "hbm": t_hbm, "power": t_pow}
        if batch1:
            limits["latency"] = t_mxu + t_vec
        t = max(limits.values())
        return dict(time_s=t, per_s=units / t, bottleneck=max(limits, key=limits.get),
                    limits_us={k: v * 1e6 for k, v in limits.items()},
                    mxu_util=self.macs / (c["macs"] * t * hz), tflops=2 * self.macs / t / 1e12,
                    energy_j=e_mac + e_hbm, hbm_gb=self.hbm / 1e9,
                    arith_j=self.macs * f["e_fj"] * 1e-15 + e_hbm)


# ------------------------------------------------------------------ GPT-2
GPT2 = {"small": (12, 768, 12), "medium": (24, 1024, 16), "large": (36, 1280, 20), "xl": (48, 1600, 25)}
VOCAB, CTX = 50257, 1024

# Vector ops per element, the compiler's lowering (docs/v3_gt2n.md, Numerics):
OPS = dict(layernorm=6, gelu=20, softmax=14, silu=20, add=1, argmax=1, maxpool5=8)


def gpt2_bytes(model):
    nl, d, _ = GPT2[model]
    weights = 2 * (nl * 12 * d * d + VOCAB * d + CTX * d)
    kv_per_token = 2 * nl * d * 2
    return weights, kv_per_token


def place(cost, sram_mb, weights, kv, reads_w, reads_kv):
    """Weights first, then the KV cache, in the SRAM; the rest is read from
    HBM reads_* times. Returns False if it fits neither."""
    sram = sram_mb * 1e6
    w_on = min(weights, sram)
    kv_on = min(kv, sram - w_on)
    if (weights - w_on) + (kv - kv_on) > CHIP["hbm_gb"] * 1e9:
        return False
    cost.hbm += (weights - w_on) * reads_w + (kv - kv_on) * reads_kv
    return True


def gpt2_layer(cost, B, Tq, Lk, d, h, causal):
    """One layer for B sequences of Tq new tokens attending to Lk keys."""
    hd = d // h
    M = B * Tq
    frac = (math.ceil(Lk / TILE) + 1) / (2 * math.ceil(Lk / TILE)) if causal else 1.0
    cost.gemm(M, d, 3 * d)
    cost.gemm(Tq, hd, Lk, count=B * h, frac=frac)
    cost.gemm(Tq, Lk, hd, count=B * h, frac=frac)
    cost.gemm(M, d, d)
    cost.gemm(M, d, 4 * d)
    cost.gemm(M, 4 * d, d)
    keys = (Lk + 1) / 2 if causal else Lk
    s = cost.f["scale_ops"]
    cost.vec(M * d * (2 * OPS["layernorm"] + 9 * OPS["add"] + 2 * OPS["add"]) + M * 4 * d * OPS["gelu"]
             + B * h * Tq * keys * OPS["softmax"] + s * M * (9 * d))


def gpt2_prefill(fmt, model, B, T):
    nl, d, h = GPT2[model]
    cost = Cost(fmt)
    w, kvt = gpt2_bytes(model)
    if not place(cost, cost.c["sram_mb"], w, kvt * B * T, 1, 1):
        return None
    for _ in range(nl):
        gpt2_layer(cost, B, T, T, d, h, causal=True)
    cost.gemm(B, d, VOCAB)
    cost.vec(B * VOCAB * OPS["argmax"])
    r = cost.result(batch1=(B == 1), units=B * T)
    r["ttft_ms"] = r["time_s"] * 1e3
    return r


def gpt2_decode(fmt, model, B, ctx):
    nl, d, h = GPT2[model]
    cost = Cost(fmt)
    w, kvt = gpt2_bytes(model)
    if not place(cost, cost.c["sram_mb"], w, kvt * B * ctx, 1, 1):
        return None
    for _ in range(nl):
        gpt2_layer(cost, B, 1, ctx, d, h, causal=False)
    cost.gemm(B, d, VOCAB)
    cost.vec(B * VOCAB * OPS["argmax"])
    r = cost.result(batch1=(B == 1), units=B)
    r["step_us"] = r["time_s"] * 1e6
    return r


# ----------------------------------------------------------------- YOLOv8
# Ultralytics scales: (depth, width, max channels)
YOLO = {"n": (0.33, 0.25, 1024), "s": (0.33, 0.50, 1024), "m": (0.67, 0.75, 768),
        "l": (1.00, 1.00, 512), "x": (1.00, 1.25, 512)}


def yolo_convs(scale, img):
    """(cin, cout, k, s, hin, act) of every convolution of test/cnn/yolo.py's
    YOLOv8 forward, at any scale and image size, with the elementwise ops."""
    dep, wid, mx = YOLO[scale]
    ch = lambda c: int(min(c, mx) * wid)                                            # noqa: E731
    rep = lambda n: max(round(n * dep), 1)                                          # noqa: E731
    convs, ew = [], {"add": 0, "maxpool5": 0}

    def conv(cin, cout, k, s, hin, act=True):
        convs.append((cin, cout, k, s, hin, act))
        return (hin + 2 * (k // 2) - k) // s + 1

    def c2f(cin, cout, n, sc, h):
        c = cout // 2
        conv(cin, 2 * c, 1, 1, h)
        for _ in range(n):
            conv(c, c, 3, 1, h)
            conv(c, c, 3, 1, h)
            if sc:
                ew["add"] += c * h * h
        conv((2 + n) * c, cout, 1, 1, h)
        return h

    c1, c2, c3, c4, c5 = ch(64), ch(128), ch(256), ch(512), ch(1024)
    h = conv(3, c1, 3, 2, img)
    h = conv(c1, c2, 3, 2, h)
    h = c2f(c2, c2, rep(3), True, h)
    h = conv(c2, c3, 3, 2, h)
    h3 = c2f(c3, c3, rep(6), True, h)
    h = conv(c3, c4, 3, 2, h3)
    h4 = c2f(c4, c4, rep(6), True, h)
    h = conv(c4, c5, 3, 2, h4)
    h5 = c2f(c5, c5, rep(3), True, h)
    conv(c5, c5 // 2, 1, 1, h5)                       # SPPF
    ew["maxpool5"] += 3 * (c5 // 2) * h5 * h5
    conv(2 * c5, c5, 1, 1, h5)
    c2f(c5 + c4, c4, rep(3), False, h4)               # 12
    c2f(c4 + c3, c3, rep(3), False, h3)               # 15: P3
    conv(c3, c3, 3, 2, h3)                            # 16
    c2f(c3 + c4, c4, rep(3), False, h4)               # 18: P4
    conv(c4, c4, 3, 2, h4)                            # 19
    c2f(c4 + c5, c5, rep(3), False, h5)               # 21: P5
    cb = max(16, c3 // 4, 64)
    cc = max(c3, 80)
    anchors = 0
    for cin, hh in ((c3, h3), (c4, h4), (c5, h5)):
        conv(cin, cb, 3, 1, hh); conv(cb, cb, 3, 1, hh); conv(cb, 64, 1, 1, hh, act=False)
        conv(cin, cc, 3, 1, hh); conv(cc, cc, 3, 1, hh); conv(cc, 80, 1, 1, hh, act=False)
        anchors += hh * hh
    return convs, ew, anchors


def yolo(fmt, scale, img, B):
    cost = Cost(fmt)
    convs, ew, anchors = yolo_convs(scale, img)
    s = cost.f["scale_ops"]
    weights = 2 * sum(co * ci * k * k for ci, co, k, _, _, _ in convs)
    act_max = max(co * ((hi + 2 * (k // 2) - k) // st + 1) ** 2 + ci * hi * hi
                  for ci, co, k, st, hi, _ in convs) * 2
    chunk = max(1, int((cost.c["sram_mb"] * 1e6 - weights) // (2 * act_max)))
    if weights > cost.c["sram_mb"] * 1e6:
        return None
    cost.hbm += B * 3 * img * img * 2 + B * anchors * 84 * 2          # images in, detections out
    for ci, co, k, st, hi, act in convs:
        ho = (hi + 2 * (k // 2) - k) // st + 1
        cost.gemm(B * ho * ho, ci * k * k, co)
        cost.vec(B * co * ho * ho * (OPS["add"] + (OPS["silu"] if act else 0)) + s * B * ci * hi * hi)
    cost.vec(B * (ew["add"] * OPS["add"] + ew["maxpool5"] * OPS["maxpool5"]
                  + anchors * (4 * 16 * OPS["softmax"] + 80 * OPS["silu"])))
    r = cost.result(batch1=(B == 1), units=B)
    r["chunk_images"] = min(chunk, B)
    r["gmacs_per_image"] = cost.macs / B / 1e9
    r["mweights"] = weights / 2 / 1e6
    return r


# ------------------------------------------------------------------- runs
def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "v3_perf.json"
    allres = {"formats": FMT, "scenarios": SCEN}
    for sc, over in SCEN.items():
        S.clear()
        S.update(over)
        allres[sc] = run()
    json.dump(allres, open(out, "w"), indent=1)
    S.clear()
    y = yolo("sf16", "n", 640, 1)
    print(f"check YOLOv8n 640: {y['gmacs_per_image']:.3f} GMACs, {y['mweights']:.2f} M weights")
    for f in FMT:
        c = chip(f)
        print(f"{f}: {c['mxus']} MXUs, {c['macs'] / 1e6:.2f} M MACs, {c['peak_tflops']:.0f} TFLOPS peak, "
              f"{c['peak_w']:.0f} W at peak, SRAM {c['sram_mb']:.0f} MB")


def v1_cases(f):
    """Section 3's v1 benchmarks: GPT-2 small, a 32-token prompt and 32
    generated tokens, and YOLOv8n on one 640 x 640 image."""
    pre = gpt2_prefill(f, "small", 1, 32)
    steps = [gpt2_decode(f, "small", 1, 32 + i) for i in range(32)]
    y = yolo(f, "n", 640, 1)
    return {"ttft_us": pre["time_s"] * 1e6, "tpot_us": sum(x["time_s"] for x in steps) / 32 * 1e6,
            "e2e_us": (pre["time_s"] + sum(x["time_s"] for x in steps)) * 1e6,
            "token_uj": sum(x["arith_j"] for x in steps) / 32 * 1e6,
            "token_uj_with_idle": sum(x["energy_j"] for x in steps) / 32 * 1e6,
            "yolo_us": y["time_s"] * 1e6, "yolo_mj": y["arith_j"] * 1e3,
            "bottlenecks": [pre["bottleneck"], steps[0]["bottleneck"], y["bottleneck"]]}


def run():
    res = {"chip": {f: chip(f) for f in FMT}, "gpt2": [], "yolo": [], "v1": {f: v1_cases(f) for f in FMT}}
    for model in GPT2:
        for B, T in [(1, 128), (1, 1024), (16, 1024), (256, 1024)]:
            res["gpt2"].append({"model": model, "phase": "prefill", "batch": B, "tokens": T,
                                **{f: gpt2_prefill(f, model, B, T) for f in FMT}})
        for B in (1, 16, 128, 1024):
            res["gpt2"].append({"model": model, "phase": "decode", "batch": B, "ctx": CTX,
                                **{f: gpt2_decode(f, model, B, CTX) for f in FMT}})
    for scale in YOLO:
        for img in (640, 1280):
            for B in (1, 64, 1024):
                res["yolo"].append({"model": f"yolov8{scale}", "img": img, "batch": B,
                                    **{f: yolo(f, scale, img, B) for f in FMT}})
    return res


if __name__ == "__main__":
    main()
