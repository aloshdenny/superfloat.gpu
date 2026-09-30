# Smoke-test LLMs for the Atreides SF16 datapath

Three language models sized to the cf-openframe chip (4 tiles x 8 threads x
8x8 array, 256 MACs, ~50 MHz, 128 B scratchpad per tile, Q1.15). They exist to
give the SF16 / FP16 / BF16 comparison a realistic switching workload and an
end-to-end bit-exactness check, not to be good language models.

## Two things to know before reading any numbers

**These will not differentiate response time.** The RTL verification already
records identical cycle counts across all three formats (2405 tile, 10397
through pins), and Fmax is set by the core at ~50 MHz rather than by the PE.
Latency therefore only moves if each variant is run at its own closed Fmax.
The honest comparison is **area and power**, where the formats genuinely
differ (PE 10.0k / 14.6k / 11.2k um^2 for SF16 / FP16 / BF16).

**A standard transformer does not fit this ISA.** There is no `exp` and no
`rsqrt`, so softmax and RMSNorm cannot be expressed. The ACT unit provides
relu, leaky relu, clipped relu and a sigmoid approximation. Every model here is
therefore a softmax-free, norm-free transformer, and the substitutions are
listed below rather than hidden.

## What had to change, and why each is sound

| standard | here | why |
| --- | --- | --- |
| softmax attention | **ReLU attention**, scores through relu then divided by their sum | no `exp` in the ISA; `asm_div` exists. Normalising by the sum keeps the output a convex combination, so it stays in [-1,1) |
| scale by 1/sqrt(d) | **scale by 1/d** | with abs(q),abs(k) < 1 the dot product is bounded by d, so 1/d is the scaling that guarantees Q1.15 range. 1/sqrt(d) does not |
| RMSNorm / LayerNorm | **nothing** | needs `rsqrt`. The residual stream is instead allowed to saturate at the Q1.15 rail |
| unbounded residual | **saturating residual** | this is what the hardware does anyway. Measured elsewhere in this project: clipping 29% of residual writes cost 0.3 points of accuracy, inside seed noise |
| learned positional embedding | **fixed, bounded** | keeps everything inside the format without a training-time constraint |

The saturating residual is the interesting one. It is not a workaround; it is
the datapath's native behaviour, and the surrounding work suggests it is close
to free at this depth. These models are the test of whether that holds for a
language model rather than a control policy.

## The three models

Dimensions are multiples of 8 so they tile onto the 8x8 array exactly, and
d_model is kept small because the chip is pin-bound: an 8x8x8 matmul takes
2405 cycles on the tile but 10397 through the pins, so roughly 4x of the time
is data movement.

| | smoke-8 | smoke-16 | smoke-32 |
| --- | --- | --- | --- |
| d_model | 8 | 16 | 32 |
| layers | 1 | 2 | 4 |
| heads | 1 | 2 | 4 |
| context | 8 | 16 | 32 |
| vocab | 16 | 32 | 64 |
| ffn | 16 | 32 | 64 |
| parameters | ~0.8k | ~5.1k | ~37k |
| MACs / token | ~0.7k | ~5.1k | ~39k |
| est. cycles / token | ~14k | ~102k | ~778k |
| est. ms / token @ 50 MHz | ~0.3 | ~2 | ~16 |

`smoke-8` is one 8x8 tile end to end and exists to prove the path and measure
per-op latency. `smoke-16` forces multi-tile decomposition. `smoke-32` is about
as large as the pin bandwidth supports: 37k parameters at 2 bytes is 74 KB per
token against roughly 12.5 MB/s through the 16-bit bus at 8 cycles per word,
which is ~6 ms of pure weight streaming per token before any arithmetic.

Cycle estimates assume the measured ~20 cycles per MAC through the pins and
should be replaced with simulated counts.

## Task

Character-level next-token prediction on a synthetic regular language, chosen
so that a model this small can actually reach high accuracy and a wrong answer
means the datapath is wrong rather than the model being too weak. Accuracy on
a held-out set is the correctness gate; bit-exactness against the Q1.15
reference is the real gate.

## Measured range behaviour

`check_range.py`, 20 random contexts per model, values decoded from
sign-magnitude before measuring:

| | embeddings | residual stream | logits | distinct argmax |
| --- | --- | --- | --- | --- |
| smoke-8 | 4.8% at rail | 15.4% | 5.6% | 7 of 16 |
| smoke-16 | 0.3% | 9.2% | 6.6% | 9 of 32 |
| smoke-32 | 0.0% | 7.9% | 5.8% | 15 of 64 |

Mean abs value lands at 0.2-0.5 and the models discriminate rather than
emitting a single token, so the architecture survives the format. The residual
clipping at 8-15% sits under the ~29% that the dogfight study in the sibling
repo found to be free, which is the reason the norm-free design is defensible
rather than reckless.

**SF16 is sign-magnitude, not two's complement.** Bit 15 is the sign and bits
0-14 the magnitude, so shifting, summing or comparing an *encoded* value is
meaningless. An earlier version of both the model and the checker did all
three: the checker counted every negative number as saturated and reported 80%
of embeddings at the rail, and the model shifted encoded negatives during
attention scaling. Anything outside the verified `helpers.q115` primitives --
the 1/d shift, the attention normalisation, argmax -- now goes through
`_sf16_to_signed` / `_signed_to_sf16`.

## Files

```
model.py        Q1.15 reference forward pass, weight generation, Config table
check_range.py  does a forward pass survive the format, or pin to the rail
```

## Status

Reference model and range validation only. Still to write:

- the synthetic task and its train/eval split
- weight export into data-memory images
- the kernels that schedule these onto 4 tiles; `test/test_inference.py`
  carries the existing matmul and MLP kernel patterns to build from
- a gate-level VCD run per format for the power comparison

Cycle and ms/token figures in the table above are estimates from the measured
~20 cycles per MAC through the pins. They are not simulated and should be
replaced before anyone quotes them.
