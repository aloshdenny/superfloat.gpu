#!/usr/bin/env python3
"""
Study S1 (docs/v3_gt2n.md): GPT-2 small on WikiText-2, every matrix multiply
run through an emulated v3 matrix unit (mxu_emu.py), per format and
accumulator, against an FP32 reference.

Only the matmuls change between cases: the linear layers, attention's QK^T
and AV per head, and the LM head. Embedding, LayerNorm, softmax, GELU, bias
and residual adds stay FP32 in every case, so the comparison isolates the
matrix unit's input format and accumulator.

Each window is a 1,024-token slice of the WikiText-2 test set (raw text,
joined with blank lines as Hugging Face's perplexity guide does); windows are
spread evenly over the set. Per case: perplexity over the 1,023 next-token
predictions per window, top-1 agreement with FP32, mean KL(FP32 || case),
and mean and maximum |logit - FP32 logit|.

  python3 s1_numerics.py [windows] [out.json]      (default 32, s1_results.json)

Results are rewritten after every window, so a stopped run keeps its data.
"""
import glob
import json
import os
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import mxu_emu as E                                               # noqa: E402

MODEL_DIR = os.environ.get("GPT2_DIR", os.path.expanduser("~/models/gpt2"))
WIKI = glob.glob(os.path.expanduser(
    "~/.cache/huggingface/hub/datasets--Salesforce--wikitext/snapshots/*/"
    "wikitext-103-raw-v1/test-00000-of-00001.parquet"))       # = WikiText-2's test set
D, HEADS, LAYERS, CTX = 768, 12, 12, 1024
HD = D // HEADS


def load_weights():
    sys.path.insert(0, os.path.join(HERE, "..", "..", "test", "gpt2"))
    from gpt2 import load_safetensors
    w = load_safetensors(os.path.join(MODEL_DIR, "model.safetensors"))
    w = {k[len("transformer."):] if k.startswith("transformer.") else k: v for k, v in w.items()}
    w["lm_head_T"] = np.ascontiguousarray(w["wte.weight"].T)
    return w


def tokens():
    import pandas as pd
    from tokenizers import Tokenizer
    text = "\n\n".join(pd.read_parquet(WIKI[0])["text"].tolist())
    tok = Tokenizer.from_file(os.path.join(MODEL_DIR, "tokenizer.json"))
    return np.array(tok.encode(text).ids, dtype=np.int64)


def layer_norm(x, g, b, eps=1e-5):
    m = x.mean(-1, keepdims=True)
    v = ((x - m) ** 2).mean(-1, keepdims=True)
    return (x - m) / np.sqrt(v + eps) * g + b


def gelu(x):
    return 0.5 * x * (1.0 + np.tanh(0.7978845608028654 * (x + 0.044715 * x ** 3)))


def forward(w, ids, mm):
    """Logits (T, vocab) for every position. mm(A, B, key) is the matmul."""
    T = len(ids)
    x = w["wte.weight"][ids] + w["wpe.weight"][:T]
    causal = np.triu(np.ones((T, T), dtype=bool), 1)
    for l in range(LAYERS):
        p = f"h.{l}."
        h = layer_norm(x, w[p + "ln_1.weight"], w[p + "ln_1.bias"])
        qkv = mm(h, w[p + "attn.c_attn.weight"], p + "c_attn") + w[p + "attn.c_attn.bias"]
        q, k, v = np.split(qkv, 3, axis=-1)
        att = np.empty((T, D), dtype=np.float32)
        for hd in range(HEADS):
            sl = slice(hd * HD, (hd + 1) * HD)
            s = mm(q[:, sl] / np.float32(8.0), np.ascontiguousarray(k[:, sl].T), None)
            s = np.where(causal, -np.inf, s)
            s = np.exp(s - s.max(-1, keepdims=True))
            pr = s / s.sum(-1, keepdims=True)
            att[:, sl] = mm(pr, np.ascontiguousarray(v[:, sl]), None)
        x = x + mm(att, w[p + "attn.c_proj.weight"], p + "attn_proj") + w[p + "attn.c_proj.bias"]
        h = layer_norm(x, w[p + "ln_2.weight"], w[p + "ln_2.bias"])
        f = gelu(mm(h, w[p + "mlp.c_fc.weight"], p + "c_fc") + w[p + "mlp.c_fc.bias"])
        x = x + mm(f, w[p + "mlp.c_proj.weight"], p + "mlp_proj") + w[p + "mlp.c_proj.bias"]
    h = layer_norm(x, w["ln_f.weight"], w["ln_f.bias"])
    return mm(h, w["lm_head_T"], "lm_head")


def log_softmax(z):
    z = z.astype(np.float64)
    z = z - z.max(-1, keepdims=True)
    return z - np.log(np.exp(z).sum(-1, keepdims=True))


def main():
    nwin = int(sys.argv[1]) if len(sys.argv) > 1 else 32
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "s1_results.json")
    cases = os.environ.get("CASES", ",".join(E.CASES)).split(",")
    w = load_weights()
    toks = tokens()
    stride = (len(toks) - CTX) // max(nwin - 1, 1)
    starts = [i * stride for i in range(nwin)]
    names = ["fp32"] + cases
    runners = {n: E.Case(n) for n in names}
    acc = {n: {"nll": 0.0, "top1": 0, "kl": 0.0, "abs_err": 0.0, "max_err": 0.0,
               "inf_or_nan": 0, "seconds": 0.0} for n in names}
    npred = 0
    for wi, s0 in enumerate(starts):
        ids = toks[s0:s0 + CTX]
        tgt = ids[1:]
        ref = None
        for n in names:
            t = time.perf_counter()
            z = forward(w, ids, runners[n].matmul)[:-1]
            acc[n]["seconds"] += time.perf_counter() - t
            bad = ~np.isfinite(z)
            acc[n]["inf_or_nan"] += int(bad.sum())
            z = np.where(bad, np.where(np.isnan(z), 0.0, np.sign(z) * 1e4), z).astype(np.float32)
            lp = log_softmax(z)
            acc[n]["nll"] += float(-lp[np.arange(len(tgt)), tgt].sum())
            if n == "fp32":
                ref, ref_lp, ref_top = z, lp, z.argmax(-1)
            acc[n]["top1"] += int((z.argmax(-1) == ref_top).sum())
            acc[n]["kl"] += float((np.exp(ref_lp) * (ref_lp - lp)).sum())
            d = np.abs(z.astype(np.float64) - ref)
            acc[n]["abs_err"] += float(d.mean()) * len(tgt)
            acc[n]["max_err"] = max(acc[n]["max_err"], float(d.max()))
        npred += len(tgt)
        res = {"windows": wi + 1, "tokens_scored": npred, "ctx": CTX, "starts": starts[:wi + 1],
               "cases": {}}
        for n in names:
            a = acc[n]
            st = runners[n].stats
            res["cases"][n] = {
                "ppl": float(np.exp(a["nll"] / npred)),
                "ppl_vs_fp32_pct": 100.0 * (np.exp((a["nll"] - acc["fp32"]["nll"]) / npred) - 1.0),
                "top1_agree": a["top1"] / npred,
                "kl_mean": a["kl"] / npred,
                "logit_abs_err_mean": a["abs_err"] / npred,
                "logit_abs_err_max": a["max_err"],
                "nonfinite_logits": a["inf_or_nan"],
                "clipped_adds": st["clips"],
                "clipped_add_rate": st["clips"] / max(st["macs"], 1),
                "headroom_bits_mean": st["headroom_bits"] / max(st["calls"], 1),
                "seconds": a["seconds"],
            }
        json.dump(res, open(out, "w"), indent=1)
        line = "  ".join(f"{n} {res['cases'][n]['ppl']:.3f}" for n in names)
        print(f"window {wi + 1}/{nwin}  {line}", flush=True)


if __name__ == "__main__":
    main()
