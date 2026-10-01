"""
GPT-2 small in numpy: weights from model.safetensors, a KV-cached forward
pass, and the inputs of every matrix multiply.

The chip runs the matrix multiplies (docs/gpt2_benchmark.md); this model supplies their
real operands and runs the operations the host does (embedding, LayerNorm,
softmax, GELU, bias and residual adds, argmax), which are also timed here.
"""
import json
import os
import struct
import time

import numpy as np

MODEL_DIR = os.environ.get("GPT2_DIR", os.path.expanduser("~/models/gpt2"))
D, HEADS, LAYERS, VOCAB, FFN = 768, 12, 12, 50257, 3072
HEAD_DIM = D // HEADS


def load_safetensors(path: str) -> dict:
    with open(path, "rb") as f:
        n = struct.unpack("<Q", f.read(8))[0]
        header = json.loads(f.read(n))
        blob = f.read()
    out = {}
    for name, meta in header.items():
        if name == "__metadata__":
            continue
        assert meta["dtype"] == "F32", (name, meta["dtype"])
        a, b = meta["data_offsets"]
        out[name] = np.frombuffer(blob[a:b], dtype=np.float32).reshape(meta["shape"])
    return out


def tokenizer():
    from tokenizers import Tokenizer
    return Tokenizer.from_file(os.path.join(MODEL_DIR, "tokenizer.json"))


class HostTimer:
    """Wall time of the host-side operations, by name."""

    def __init__(self):
        self.t = {}

    def add(self, name, dt):
        self.t[name] = self.t.get(name, 0.0) + dt


def layer_norm(x, g, b, eps=1e-5):
    m = x.mean(-1, keepdims=True)
    v = ((x - m) ** 2).mean(-1, keepdims=True)
    return (x - m) / np.sqrt(v + eps) * g + b


def gelu(x):
    return 0.5 * x * (1.0 + np.tanh(0.7978845608028654 * (x + 0.044715 * x ** 3)))


class GPT2:
    def __init__(self, path: str = None):
        w = load_safetensors(path or os.path.join(MODEL_DIR, "model.safetensors"))
        self.w = {k[len("transformer."):] if k.startswith("transformer.") else k: v for k, v in w.items()}

    def W(self, name):
        return self.w[name]

    def forward(self, ids, cache, timer=None, record=None):
        """Run tokens `ids` after those already in `cache` (per-layer K and V
        lists). Returns the logits of the last token. `record`, if a dict,
        receives the inputs of every matrix multiply: (layer, op) -> array."""
        tm = timer or HostTimer()
        w = self.w
        pos0 = len(cache[0][0]) if cache[0][0] is not None else 0
        T = len(ids)

        t = time.perf_counter()
        x = w["wte.weight"][ids] + w["wpe.weight"][pos0:pos0 + T]
        tm.add("embedding", time.perf_counter() - t)

        for l in range(LAYERS):
            p = f"h.{l}."
            t = time.perf_counter()
            h = layer_norm(x, w[p + "ln_1.weight"], w[p + "ln_1.bias"])
            tm.add("layernorm", time.perf_counter() - t)
            if record is not None:
                record[(l, "c_attn")] = h
            qkv = h @ w[p + "attn.c_attn.weight"]
            t = time.perf_counter()
            qkv = qkv + w[p + "attn.c_attn.bias"]
            tm.add("bias_residual", time.perf_counter() - t)
            q, k, v = np.split(qkv, 3, axis=-1)
            K = k if cache[l][0] is None else np.concatenate([cache[l][0], k])
            V = v if cache[l][1] is None else np.concatenate([cache[l][1], v])
            cache[l] = (K, V)
            L = len(K)
            att = np.zeros((T, D), dtype=np.float32)
            for hd in range(HEADS):
                sl = slice(hd * HEAD_DIM, (hd + 1) * HEAD_DIM)
                qh = q[:, sl] / np.sqrt(HEAD_DIM)
                if record is not None:
                    record[(l, f"qk{hd}")] = (qh, K[:, sl])
                s = qh @ K[:, sl].T
                t = time.perf_counter()
                mask = np.arange(L)[None, :] > (pos0 + np.arange(T))[:, None]
                s = np.where(mask, -1e9, s)
                s = np.exp(s - s.max(-1, keepdims=True))
                pr = s / s.sum(-1, keepdims=True)
                tm.add("softmax", time.perf_counter() - t)
                if record is not None:
                    record[(l, f"av{hd}")] = (pr, V[:, sl])
                att[:, sl] = pr @ V[:, sl]
            if record is not None:
                record[(l, "attn_proj")] = att
            o = att @ w[p + "attn.c_proj.weight"]
            t = time.perf_counter()
            x = x + o + w[p + "attn.c_proj.bias"]
            tm.add("bias_residual", time.perf_counter() - t)
            t = time.perf_counter()
            h = layer_norm(x, w[p + "ln_2.weight"], w[p + "ln_2.bias"])
            tm.add("layernorm", time.perf_counter() - t)
            if record is not None:
                record[(l, "c_fc")] = h
            f = h @ w[p + "mlp.c_fc.weight"]
            t = time.perf_counter()
            f = gelu(f + w[p + "mlp.c_fc.bias"])
            tm.add("gelu", time.perf_counter() - t)
            if record is not None:
                record[(l, "mlp_proj")] = f
            o = f @ w[p + "mlp.c_proj.weight"]
            t = time.perf_counter()
            x = x + o + w[p + "mlp.c_proj.bias"]
            tm.add("bias_residual", time.perf_counter() - t)

        t = time.perf_counter()
        h = layer_norm(x[-1:], w["ln_f.weight"], w["ln_f.bias"])
        tm.add("layernorm", time.perf_counter() - t)
        if record is not None:
            record[(LAYERS, "lm_head")] = h
        logits = h @ w["wte.weight"].T
        t = time.perf_counter()
        tok = int(np.argmax(logits[-1]))
        tm.add("argmax", time.perf_counter() - t)
        return logits[-1], tok


def new_cache():
    return [(None, None) for _ in range(LAYERS)]
