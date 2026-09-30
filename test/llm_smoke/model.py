"""Q1.15 reference forward pass for the smoke-test LLMs.

Bit-exact against the hardware by construction: every arithmetic operation goes
through the same `helpers.q115` primitives the RTL is verified against, so this
doubles as the expected-output generator for the testbench.

The architecture is softmax-free and norm-free because the ISA has no `exp` and
no `rsqrt`. See README.md for each substitution and why it preserves the Q1.15
range.
"""
from __future__ import annotations

import math
import os
import sys

# Load helpers/q115.py directly. Importing `helpers` as a package pulls in
# cocotb via its __init__, which is not available outside the simulator, and
# this reference has to run standalone to generate expected outputs.
import importlib.util as _ilu

_q115_path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          "..", "helpers", "q115.py")
_spec = _ilu.spec_from_file_location("q115", _q115_path)
_q115 = _ilu.module_from_spec(_spec)
_spec.loader.exec_module(_q115)

float_to_q115 = _q115.float_to_q115
q115_to_float = _q115.q115_to_float
q115_mul = _q115.q115_mul
q115_add = _q115.q115_add
q115_fma = _q115.q115_fma
q115_relu = _q115.q115_relu
Q115_MAX = _q115.Q115_MAX
# SF16 is SIGN-MAGNITUDE, not two's complement: bit 15 is the sign and bits
# 0-14 the magnitude. Shifting, summing or comparing an ENCODED value is
# therefore meaningless. Anything this file does outside the verified helpers
# -- the 1/d shift, the attention normalisation, argmax -- goes through these.
to_signed = _q115._sf16_to_signed
from_signed = _q115._signed_to_sf16

Q115_MIN = -(Q115_MAX + 1)


class Config:
    def __init__(self, name, d, layers, heads, ctx, vocab, ffn):
        self.name, self.d, self.layers = name, d, layers
        self.heads, self.ctx, self.vocab, self.ffn = heads, ctx, vocab, ffn
        assert d % 8 == 0 or d == 8, "dims are multiples of 8 to tile the 8x8 array"
        assert d % heads == 0
        self.head_dim = d // heads

    def n_params(self):
        emb = self.vocab * self.d + self.ctx * self.d
        per_layer = 4 * self.d * self.d + 2 * self.d * self.ffn
        return emb + self.layers * per_layer + self.d * self.vocab

    def macs_per_token(self):
        attn = 4 * self.d * self.d + self.ctx * self.d * 2
        ffn = 2 * self.d * self.ffn
        return self.layers * (attn + ffn) + self.d * self.vocab


CONFIGS = {
    "smoke-8":  Config("smoke-8",  8,  1, 1,  8, 16, 16),
    "smoke-16": Config("smoke-16", 16, 2, 2, 16, 32, 32),
    "smoke-32": Config("smoke-32", 32, 4, 4, 32, 64, 64),
}


# --------------------------------------------------------------------------
# Q1.15 primitives built from the verified helpers
# --------------------------------------------------------------------------

def sat(signed_val):
    """Saturate a SIGNED Python int back into the SF16 sign-magnitude encoding."""
    return from_signed(signed_val)


def dot(a, b):
    """Accumulate in 32 bits, saturate back into Q1.15 -- the datapath's shape."""
    acc = 0
    for x, y in zip(a, b):
        acc = q115_fma(acc, x, y)
    return acc


def matvec(W, x):
    """W is [out][in] in Q1.15; x is [in]."""
    return [dot(row, x) for row in W]


def scale_by_inv_d(v, d):
    """Divide by d; d is a power of two, so this is a shift of the MAGNITUDE."""
    sh = int(math.log2(d))
    return [from_signed(to_signed(x) >> sh) for x in v]


def relu_attention(q, K, V, d):
    """ReLU attention: scores -> relu -> normalise by their sum.

    Softmax needs `exp`, which the ISA does not have. Taking relu and dividing
    by the sum keeps the output a convex combination of the values, so it stays
    inside Q1.15 without any further clamping.
    """
    scores = [dot(q, k) for k in K]
    scores = scale_by_inv_d(scores, d)
    scores = [q115_relu(s) for s in scores]
    sgn = [to_signed(s) for s in scores]           # relu output is >= 0
    total = sum(sgn)
    if total == 0:
        return [0] * len(V[0])                     # nothing selected this step
    out = []
    for j in range(len(V[0])):
        acc = 0
        for sv, vec in zip(sgn, V):
            # (s / total) * v[j] as an integer divide, matching asm_div
            acc += (sv * to_signed(vec[j])) // total
        out.append(from_signed(acc))
    return out


def block(x_seq, W, cfg):
    """One transformer block: ReLU attention + FFN, both with saturating residual."""
    T = len(x_seq)
    Q = [matvec(W["wq"], x) for x in x_seq]
    K = [matvec(W["wk"], x) for x in x_seq]
    V = [matvec(W["wv"], x) for x in x_seq]

    attn = []
    for t in range(T):
        heads = []
        for h in range(cfg.heads):
            lo, hi = h * cfg.head_dim, (h + 1) * cfg.head_dim
            # causal: only positions up to t
            kh = [k[lo:hi] for k in K[: t + 1]]
            vh = [v[lo:hi] for v in V[: t + 1]]
            heads.extend(relu_attention(Q[t][lo:hi], kh, vh, cfg.head_dim))
        attn.append(matvec(W["wo"], heads))

    # saturating residual: this is what the register does, not an approximation
    h1 = [[q115_add(a, b) for a, b in zip(x, y)] for x, y in zip(x_seq, attn)]

    out = []
    for x in h1:
        hidden = [q115_relu(v) for v in matvec(W["w1"], x)]
        y = matvec(W["w2"], hidden)
        out.append([q115_add(a, b) for a, b in zip(x, y)])
    return out


def forward(tokens, W, cfg):
    """Token ids -> logits for the final position."""
    x = [[q115_add(W["emb"][t][i], W["pos"][p][i]) for i in range(cfg.d)]
         for p, t in enumerate(tokens)]
    for l in range(cfg.layers):
        x = block(x, W["layers"][l], cfg)
    return matvec(W["head"], x[-1])


def argmax_q115(logits):
    """Argmax over SF16 words: compare in signed space, not on the encoding."""
    return max(range(len(logits)), key=lambda i: to_signed(logits[i]))


# --------------------------------------------------------------------------
# Weights
# --------------------------------------------------------------------------

def init_weights(cfg, seed=0):
    """Deterministic Q1.15 weights, scaled so activations stay in range.

    std = 1/sqrt(fan_in) keeps a dot product of fan_in terms order 1, which is
    the whole budget in Q1.15. Values are clamped into the grid at init rather
    than relying on saturation to do it.
    """
    import random
    r = random.Random(seed)

    def mat(out_dim, in_dim):
        s = 1.0 / math.sqrt(in_dim)
        return [[float_to_q115(max(-0.99, min(0.99, r.gauss(0, s))))
                 for _ in range(in_dim)] for _ in range(out_dim)]

    W = {
        "emb": mat(cfg.vocab, cfg.d),
        "pos": mat(cfg.ctx, cfg.d),
        "head": mat(cfg.vocab, cfg.d),
        "layers": [],
    }
    for _ in range(cfg.layers):
        W["layers"].append({
            "wq": mat(cfg.d, cfg.d), "wk": mat(cfg.d, cfg.d),
            "wv": mat(cfg.d, cfg.d), "wo": mat(cfg.d, cfg.d),
            "w1": mat(cfg.ffn, cfg.d), "w2": mat(cfg.d, cfg.ffn),
        })
    return W


def flatten_weights(W, cfg):
    """Row-major Q1.15 word list for the data-memory image."""
    out = []
    for row in W["emb"]:
        out.extend(row)
    for row in W["pos"]:
        out.extend(row)
    for L in W["layers"]:
        for k in ("wq", "wk", "wv", "wo", "w1", "w2"):
            for row in L[k]:
                out.extend(row)
    for row in W["head"]:
        out.extend(row)
    return out


if __name__ == "__main__":
    print("%-10s %8s %9s %10s %12s %14s" %
          ("model", "params", "MACs/tok", "words", "est cycles", "ms/tok @50MHz"))
    for name, cfg in CONFIGS.items():
        W = init_weights(cfg)
        words = len(flatten_weights(W, cfg))
        cyc = cfg.macs_per_token() * 20          # measured ~20 cycles/MAC via pins
        print("%-10s %8d %9d %10d %12d %14.2f" %
              (name, cfg.n_params(), cfg.macs_per_token(), words, cyc, cyc / 50e6 * 1e3))
