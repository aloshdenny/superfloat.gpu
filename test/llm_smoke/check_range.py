"""Does a forward pass survive Q1.15, or does everything pin to the rail?

The design keeps values in range by construction (1/d attention scaling,
convex-combination attention, 1/sqrt(fan_in) init). This checks that claim on
real activations instead of trusting the arithmetic.
"""
import random, sys
from model import (CONFIGS, init_weights, forward, matvec, block, Q115_MAX,
                   q115_to_float, argmax_q115)
from model import q115_add

def stats(name, vals):
    """Stats on DECODED values. Doing this on the sign-magnitude encoding
    counts every negative number as saturated, which is how an earlier version
    reported 80% of embeddings at the rail when nothing was wrong."""
    f = [abs(q115_to_float(v)) for v in vals]
    n = len(f)
    rail = sum(1 for v in f if v >= (Q115_MAX - 1) / 32768.0)
    mx = max(f); mean = sum(f) / n
    print("  %-22s n=%-7d peak=%.3f  mean|x|=%.4f  at-rail=%5.2f%%" %
          (name, n, mx, mean, 100 * rail / n))

for cname, cfg in CONFIGS.items():
    print("\n=== %s (d=%d, L=%d, ctx=%d) ===" % (cname, cfg.d, cfg.layers, cfg.ctx))
    W = init_weights(cfg, seed=0)
    r = random.Random(1)
    emb_all, resid_all, logit_all = [], [], []
    for trial in range(20):
        toks = [r.randrange(cfg.vocab) for _ in range(cfg.ctx)]
        x = [[q115_add(W["emb"][t][i], W["pos"][p][i]) for i in range(cfg.d)]
             for p, t in enumerate(toks)]
        for row in x: emb_all.extend(row)
        for l in range(cfg.layers):
            x = block(x, W["layers"][l], cfg)
            for row in x: resid_all.extend(row)
        logit_all.extend(matvec(W["head"], x[-1]))
    stats("embedding+pos", emb_all)
    stats("residual stream", resid_all)
    stats("output logits", logit_all)
    # is the model discriminative, or does argmax always pick the same token?
    preds = []
    for trial in range(60):
        toks = [r.randrange(cfg.vocab) for _ in range(cfg.ctx)]
        lg = forward(toks, W, cfg)
        preds.append(argmax_q115(lg))
    print("  distinct argmax over 60 random inputs: %d of %d vocab" %
          (len(set(preds)), cfg.vocab))
