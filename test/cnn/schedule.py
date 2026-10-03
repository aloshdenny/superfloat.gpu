"""
Every chip launch of one YOLOv8n image (docs/cnn_benchmark.md).

Each convolution is a GEMM, out (Cout x HW) = W (Cout x K) @ patches (K x HW),
run by the gemm kernel (test/gpt2/kernels.py), whose block computes an 8 x 8
output tile as an outer product per k. A block here is 8 output channels by
8 output pixels: the channels' weights are the kernel's shared operand
(stored once per launch) and each block has its own 8 pixels' patches.

  - K above KMAX runs as equal chunks, at most KMAX each, whose partial sums
    the host adds (as GPT-2's FC2 does). Odd K is padded with a zero.
  - A launch covers one 8-channel group and as many 8-pixel blocks as the
    data window holds (weights 8K, per block patches 8K and 64 outputs), up
    to 31 blocks, the thread-count limit. The window ends at WINDOW_TOP:
    0xFFC0..0xFFFF is each core's own scratchpad (src/core_tile.sv), so
    stores there never reach the host.

  launches(model) -> [(kernel, kc, nb), ...] for one image
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "gpt2"))
import kernels as KN                                      # noqa: E402

KMAX = 768
WINDOW_TOP = 0xFFC0


def chunks(K):
    """K split into equal even chunks of at most KMAX."""
    n = math.ceil(K / KMAX)
    kc = math.ceil(K / n)
    kc += kc % 2
    return [kc] * n


def blocks_per_launch(kc):
    room = WINDOW_TOP - KN.TABLE_WORDS - KN.N * kc
    return min(KN.MAX_BLOCKS, room // (KN.N * kc + KN.N * KN.N))


def conv_launches(conv):
    """(kernel, kc, nb) of every launch of one convolution."""
    out = []
    groups = conv.cout // KN.N
    assert conv.cout % KN.N == 0 and conv.N % KN.N == 0, conv.name
    pix_blocks = conv.N // KN.N
    for kc in chunks(conv.K):
        nbm = blocks_per_launch(kc)
        full, rem = divmod(pix_blocks, nbm)
        per_group = [("gemm", kc, nbm)] * full + ([("gemm", kc, rem)] if rem else [])
        out += per_group * groups
    return out


def launches(model):
    return [l for c in model.convs for l in conv_launches(c)]


if __name__ == "__main__":
    from collections import Counter
    from yolo import Model, image
    m = Model()
    m.forward(image())
    ls = launches(m)
    shapes = Counter(ls)
    print(f"{len(ls)} launches, {len(shapes)} shapes, "
          f"{sum(nb for _, _, nb in ls)} blocks")
    for (k, kc, nb), n in sorted(shapes.items(), key=lambda s: (s[0][1], s[0][2])):
        print(f"  {k}_{kc}_{nb}: {n}")
