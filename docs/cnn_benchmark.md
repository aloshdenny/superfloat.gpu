# YOLOv8n on the OpenFrame chips

YOLOv8n (Ultralytics, 640 × 640) on the three v1 chips, SF16, FP16 and BF16, measured the way `docs/gpt2_benchmark.md` measures GPT-2. The chip runs every convolution; the host does everything else. Detection quality is not measured; latency, cycles, clock and energy are.

## Results (v1 chips)

One 640 × 640 image. Each chip runs at its guaranteed peak clock: the worst signoff corner, ss, 100 °C, 1.60 V.

| | SF16 | FP16 | BF16 |
|---|---|---|---|
| Peak clock (ss, guaranteed) | 51.9 MHz | **55.7 MHz** | 54.1 MHz |
| Time per image | 205.0 s | **191.2 s** | 196.6 s |
| Time per image, typical corner (tt) | 121.2 s | **120.0 s** | 122.2 s |
| Chip power (gemm kernel, 50 MHz, typical corner) | **250.5 mW** | 459.6 mW | 440.5 mW |
| Energy per image | **53.3 J** | 97.8 J | 93.7 J |

- **Speed follows the clock alone.** The cycle count is identical in all three formats: every launch shape was simulated in each and matched. FP16 is fastest by its clock: 7% ahead of SF16, 3% ahead of BF16.
- **SF16 uses 45% less energy** than FP16, and 43% less than BF16. The ratios are GPT-2's: the same kernel, on the same tiles.
- **The host's share is negligible:** 148 ms per image, against about 200 s on the chip.

### Cycles (identical in every format)

| | |
|---|---|
| Convolutions | 63 (4.371 GMACs, 8.74 GFLOPs; 3.15 M weights) |
| Launches per image | 12,218, in 41 shapes; 246,900 thread blocks |
| Cycles per image | 10.637 G |
| Bus transfers per image | 1.099 G reads (0.251 per MAC), 15.8 M writes |
| Cycles per bus transfer | 9.41 |
| Array use | 0.411 MACs per cycle of a 256-MAC peak: 0.161% |

- **The image is bus-bound,** as GPT-2's prefill is. Each block reads 16 words per k for 64 MACs, so cycles follow MACs: the backbone takes 36.1% of the cycles for 36.1% of the MACs, the neck 22.2% for 22.5%, the detection head 41.7% for 41.4%.
- **3 × 3 convolutions take 81% of the cycles.** The largest are the head's 80 × 80 layers, K = 576 and 720: `22.cv3.0.1` alone is 8.2% (877 M cycles).
- **Against GPT-2:** one image costs 1.46 × a 32-token GPT-2 prefill (7.281 G cycles), at a similar 0.41 MACs per cycle (prefill: 0.37).

### Host, per image (numpy, this machine)

| SiLU | im2col | Box decode | Bias | Upsample | Max-pool | Concat | Residual add | Total |
|---|---|---|---|---|---|---|---|---|
| 58 ms | 48 ms | 23 ms | 10 ms | 4 ms | 3 ms | 1 ms | 0.3 ms | 148 ms |

## What runs where

| | Chip | Host |
|---|---|---|
| Work | Every convolution (63), as a matrix multiply | im2col, folded-batch-norm bias, SiLU, residual adds, SPPF max-pools, upsampling, concatenation, the detection head's decode (DFL softmax, boxes, sigmoid scores) |
| Data | Reads weights and patches over the pin bus; writes outputs back | Holds the weights and the activations in RAM |

The ISA has no exp or divide, so SiLU, the softmax of the box decode and the sigmoid scores run on the host, as GPT-2's GELU and softmax do.

## Mapping

A convolution is a GEMM: out (Cout × H·W) = W (Cout × K) @ patches (K × H·W), K = Cin × k × k (`test/cnn/schedule.py`).

- **Kernel:** GPT-2's prefill kernel (`gemm`, `test/gpt2/kernels.py`). A block computes an 8 × 8 tile as an outer product per k. Here a block is 8 output channels by 8 output pixels: the channels' weights are the shared operand, stored once per launch, and each block reads its own pixels' patches.
- **K above 768** runs as equal chunks of at most 768, whose partial sums the host adds (as GPT-2's FC2 does). The 3 × 3 layers on 128 and 256 channels are the only ones.
- **A launch** is one 8-channel group and as many 8-pixel blocks as the data window holds, up to 31 (the thread-count limit): 31 blocks up to K = 192, 9 at K = 768.
- **The window ends at 0xFFC0.** 0xFFC0–0xFFFF is each core's own scratchpad (`src/core_tile.sv`); stores there never reach the host. GPT-2's launches never reached it. The first YOLO run of K = 256 (30 blocks) did: 32 of its 1,920 outputs never arrived. It now takes 29 blocks.

## Measurements

- **Cycles.** Every launch shape one image uses was run through the RTL chip's pins in all three formats (`make test_gpt2_bench NUMBER_FORMAT=<0|1|2> GPT2_LAUNCHES=yolo_gemm_<kc>_<nb>`), with every output checked bit for bit (`test/cnn/results/v1_<fmt>.jsonl`; 123 runs, 50 hours of simulation). Nothing comes from a fit.
  - Operands are real activations of the network, laid out by `test/cnn/prepare.py`: the first 8 output channels of a convolution with that K, and the patches of its first output pixels.
  - The weights are synthetic: seeded, He-scaled, batch norm folded (`test/cnn/yolo.py`); the input is a synthetic image. Cycle counts do not depend on the values.
  - Per image: the sum over its 12,218 launches of the measured cycles plus the 7-cycle gap between launches.
  - The host answers each bus beat on the next falling edge (`HOST_LATENCY=0`), as for GPT-2.
- **Peak clock.** 1 / (20 ns − worst setup slack) over the chip and its tile, from the v1 signoff STA, as for GPT-2.
- **Power.** The `gemm` kernel's chip power from the v1 gate-level runs (`test/gpt2/power/results/<fmt>_gemm.json`, cf-openframe): OpenSTA on the signed-off netlists' switching activity, with signoff parasitics, at nom_tt_025C_1v80 and 50 MHz. YOLO runs that kernel and nothing else.
  - Those runs used GPT-2 operands, not YOLO's. The kernel's power barely depends on them: GPT-2's prefill and decode kernels differ by 0.1%, because the clock tree and flops dominate. A gate-level run on YOLO operands has not been made.
- **Energy.** Power × time at 50 MHz. Dynamic power scales with the clock, so the energy per image does not depend on it.
- **Host.** `yolo.py`'s numpy time for the host's operations on the machine that ran the benchmark, reported as its own line.

`python3 test/cnn/bench.py --gen v1` recomputes the tables (`test/cnn/results/summary_v1.json`).
