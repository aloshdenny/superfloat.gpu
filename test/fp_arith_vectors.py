"""
Test vectors for src/fp_arith.sv: a, b, c and the expected round(a*b + c).

usage: python3 test/fp_arith_vectors.py fp16|bf16 COUNT OUT.hex [SEED]

The mix is weighted towards the hard cases of a fused multiply-add: raw bit
patterns (NaN, infinities, subnormal encodings), near-exact cancellation,
addends within a few binades of the product, results near the smallest
normal and near overflow, far-apart exponents (sticky bit), and plain adds.
Expected results come from helpers/fp16fmt.py.
"""
import os
import random
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "helpers"))
from fp16fmt import FORMATS          # direct import: the helpers package needs cocotb


def vectors(F, n, seed):
    rnd = random.Random(seed)
    W, M = F.width, F.m
    mask = (1 << W) - 1
    sign_bit = 1 << (W - 1)

    def normal(elo=1, ehi=None):
        elo = max(1, elo)
        ehi = F.emax_field - 1 if ehi is None else min(F.emax_field - 1, ehi)
        return (rnd.getrandbits(1) << (W - 1)) | (rnd.randint(elo, ehi) << M) | rnd.getrandbits(M)

    specials = [0, sign_bit, F.inf(0), F.inf(1), F.qnan, F.qnan | sign_bit, F.qnan + 1,
                1, (1 << M) - 1, 1 << M, ((F.emax_field - 1) << M) | ((1 << M) - 1),
                F.one(), F.one() | sign_bit]
    for i in range(n):
        k = i % 8
        if k == 0:                                   # raw bit patterns
            a, b, c = (rnd.getrandbits(W) for _ in range(3))
        elif k == 1:                                 # specials mixed in
            a, b, c = (rnd.choice(specials) if rnd.random() < 0.4 else rnd.getrandbits(W)
                       for _ in range(3))
        elif k == 2:                                 # c ~ -a*b
            a, b = normal(F.bias - 4, F.bias + 4), normal(F.bias - 4, F.bias + 4)
            c = F.fma(a, b, 0) ^ sign_bit
            if rnd.random() < 0.7 and (c >> M) & F.emax_field not in (0, F.emax_field):
                c = (c + rnd.randint(-3, 3)) & mask
        elif k == 3:                                 # addend near the product
            a, b = normal(F.bias - 3, F.bias + 3), normal(F.bias - 3, F.bias + 3)
            c = normal(F.bias - 6, F.bias + 6)
        elif k == 4:                                 # near the smallest normal
            a, b = normal(1, F.bias), normal(1, F.bias + 2)
            c = normal(1, 4) if rnd.random() < 0.7 else rnd.getrandbits(1) << (W - 1)
        elif k == 5:                                 # near overflow
            a = normal(F.emax_field - 1 - F.bias // 2 - 2, F.emax_field - 1)
            b = normal(F.bias + F.bias // 2 - 2, F.bias + F.bias // 2 + 2)
            c = normal(F.emax_field - 4, F.emax_field - 1)
        elif k == 6:                                 # any exponents (sticky paths)
            a, b, c = normal(), normal(), normal()
        else:                                        # additions: a * 1.0 + c
            a, b, c = normal(), F.one(), normal()
            if rnd.random() < 0.5:
                ea = (a >> M) & F.emax_field
                c = (a ^ sign_bit) if rnd.random() < 0.3 else normal(ea - 12, ea + 12)
        yield a, b, c, F.fma(a, b, c)


def main():
    name, n, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    seed = int(sys.argv[4]) if len(sys.argv) > 4 else 1234
    with open(out, "w") as f:
        for a, b, c, r in vectors(FORMATS[name], n, seed):
            f.write(f"{a:04x} {b:04x} {c:04x} {r:04x}\n")


if __name__ == "__main__":
    main()
