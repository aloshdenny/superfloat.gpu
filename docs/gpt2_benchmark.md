# GPT-2 on the OpenFrame chips

GPT-2 small (124M parameters) on the three signed-off OpenFrame chips: SF16, FP16 and BF16. The chip runs every matrix multiply, with the model streamed a layer at a time from host memory over the 16-bit pin bus. The host does everything else. Response quality is not measured; latency, cycles, clock and energy are.

## Results

GPT-2 small, prompts of 8, 32 and 128 tokens, 32 generated tokens. Each chip runs at its guaranteed peak clock: the worst signoff corner, ss, 100 °C, 1.60 V.

### Headline: 32-token prompt, 32 generated tokens

| | SF16 | FP16 | BF16 |
|---|---|---|---|
| Peak clock (ss, guaranteed) | 51.9 MHz | **55.7 MHz** | 54.1 MHz |
| Prefill / time to first token | 140.2 s | **130.8 s** | 134.5 s |
| Time per output token | 21.3 s | **19.9 s** | 20.4 s |
| Decode throughput | 0.047 tok/s | **0.050 tok/s** | 0.049 tok/s |
| End to end, 32 + 32 tokens | 800 s | **747 s** | 768 s |
| Chip power (decode, 50 MHz, typical corner) | **251 mW** | 460 mW | 441 mW |
| Energy per decode token | **5.55 J** | 10.17 J | 9.74 J |
| Energy, 32 + 32 tokens | **209 J** | 382 J | 366 J |

- **Speed follows the clock alone.** Cycle counts are identical in all three formats, so FP16 is fastest by its clock: 7% ahead of SF16, and 3% ahead of BF16.
- **SF16 uses 45% less energy** than FP16, and 43% less than BF16. Its tiles draw 61 mW against 113 mW and 108 mW, because the FP tiles carry about 1.8× SF16's flops and clock tree.
- **The host's share is negligible.** LayerNorm, softmax, GELU, embedding and argmax take 1.6–2.0 ms of host time per token, against about 20 s on the chip.

### Cycles (identical in every format)

| Phase | Cycles | Launches | Cycles per prompt token |
|---|---|---|---|
| Decode, one token (context 9–159) | 1,100–1,124 M | 2,105–2,177 | — |
| Prefill, 8 tokens | 2,073 M | 2,249 | 259 M |
| Prefill, 32 tokens | 7,281 M | 7,133 | 228 M |
| Prefill, 128 tokens | 28,368 M | 27,089 | 222 M |

- **Decode is bus-bound.** A token streams 124 M weights over the 16-bit pin bus at 1.125 reads per weight and about 7.8 cycles per transfer.
  - The arrays do 0.11 MACs per cycle against a peak of 256: 0.044% utilisation, 5.8–6.2 M MAC/s.
- **Prefill is cheaper per token than decode:** 222–259 M cycles per prompt token against about 1,100 M, about 4.8× fewer. The prefill kernel reads each weight once per 8 tokens, but it also reads every token's activations once per column block, so 8 tokens cost about 1.9 decode tokens.
- **Attention is a small share.** It grows with context: 0.30% of a decode token at context 9, 1.0% at 63, 2.4% at 159.

### Time to first token and end to end, by prompt length

| Prompt | | SF16 | FP16 | BF16 |
|---|---|---|---|---|
| 8 tokens | TTFT | 39.9 s | 37.2 s | 38.3 s |
| | End to end (+32) | 698 s | 651 s | 669 s |
| | Energy | 182 J | 333 J | 319 J |
| 32 tokens | TTFT | 140.2 s | 130.8 s | 134.5 s |
| | End to end (+32) | 800 s | 747 s | 768 s |
| | Energy | 209 J | 382 J | 366 J |
| 128 tokens | TTFT | 546 s | 510 s | 524 s |
| | End to end (+32) | 1,216 s | 1,134 s | 1,166 s |
| | Energy | 317 J | 581 J | 556 J |

At a common 50 MHz clock all three take the same time: TTFT of 41.5 s, 145.6 s and 567.4 s for the three prompt lengths.

### Clock

| | SF16 | FP16 | BF16 |
|---|---|---|---|
| Peak clock, worst corner (ss, 100 °C, 1.60 V) | 51.9 MHz | 55.7 MHz | 54.1 MHz |
| Limited by | Tile: a wire-dominated path, LSU address to activation output (11 of 37 stages are repair buffers, 3.4 ns) | Tile: FP PE adder (pure logic, no buffers) | Tile: FP activation unit (10 of 35 stages are buffers) |
| Peak clock, typical corner (tt, 25 °C, 1.80 V) | 87.9 MHz | 88.8 MHz | 87.1 MHz |
| Limited by | Chip: `bus_req` under the 4 ns board output-delay budget | Same | Same |

All three were hardened at 20 ns, and the tools stop optimising once a clock is met. These are the peak clocks of these layouts, not of the formats (`docs/evals.md`).

### Power, per tile (decode, gate level, 50 MHz, nom_tt)

| | SF16 | FP16 | BF16 |
|---|---|---|---|
| Clock tree | 40.1 mW | 75.9 mW | 72.8 mW |
| Sequential | 19.9 mW | 36.5 mW | 34.2 mW |
| Combinational | 0.68 mW | 0.85 mW | 0.70 mW |
| Tile total | **60.7 mW** | 113.0 mW | 108.0 mW |
| Chip top level | 8.2 mW | 7.7 mW | 8.6 mW |
| Chip (top + 4 tiles) | **251.0 mW** | 459.7 mW | 440.6 mW |

- **Prefill draws the same power as decode,** within 0.1%: the clock tree and flops dominate, and the datapath is mostly idle.
- **Annotation coverage:**
  - every tile pin was annotated from the gate-level activity;
  - 94.5% of top-level pins were. The rest are macro pins, tie cells, CTS dummy loads and port-vector nets.

### Host latency

Measured on the 4-block decode launch, SF16: 210,885 / 237,059 / 263,328 / 307,663 cycles with the host answering after 0 / 1 / 2 / 4 extra cycles. Each extra cycle of host latency costs about 0.8–0.95 cycles per bus transfer. The figures above assume the ideal host (0).

### Sources

- Cycles: every launch shape the scenarios use was simulated through the RTL chip's pins, with every output checked bit for bit (`test/gpt2/results/<fmt>.jsonl`).
  - 19 shapes were run in all three formats and matched exactly.
  - Attention shapes were simulated on SF16 and reused for FP16 and BF16 (`bench.py`, `format_check`). None came from a fit.
- Power: `test/gpt2/power/results/`.
- Summary: `test/gpt2/results/summary.json`.

## What runs where

| | Chip | Host |
|---|---|---|
| Work | Every matrix multiply: QKV, attention scores, attention × V, attention projection, both MLP layers, LM head | Embedding lookup, LayerNorm, softmax, GELU, bias and residual adds, argmax |
| Data | Reads weights and activations over the pin bus; writes outputs back | Holds the model, the KV cache and the activations in RAM |

- **Why the split.** The ISA has no exp, rsqrt, GELU or general divide (`src/decoder.sv`, `src/alu.sv`), so LayerNorm, softmax and GELU cannot run on the chip as GPT-2 defines them. A special-function unit is planned as v2.
- **Cost of the split.** The host's operations touch only activations: a few thousand words per layer, against about 7 million weight words the chip streams per layer per token.

## Kernels

Both kernels are in `test/gpt2/kernels.py`, with bit-exact Python references. Each thread block computes 8 output columns on its tile's 8×8 array.

- **Decode, one token (`gemv`).**
  - Row r of the array holds weight row k0 + r, and thread i drives x[k0 + i]. Each array compute is 64 MACs for 8 activation words and 64 weight words: 1.125 bus reads per weight.
  - After the K loop, thread j sums column j over the 8 rows (SYS read, ACT add) and stores y[j].
  - The loop is 29 instructions, so it stays in the 32-entry instruction cache.
- **Prefill, 8 tokens (`gemm`).**
  - Every row holds weight row k (8 SYS loads of the same word) and thread i drives token i's activation, so the array computes an outer product per k.
  - 0.25 bus reads per MAC.
- **No flush.** SYS load also takes the activation operand, so loading x before the weights settles every column before the compute (the SYS operand hold in `src/core.sv`).
- **Launch window.** The chip addresses 64K data words, so the host maps each launch's operands into a window:
  - a block table (x, weight and output base per block);
  - the operands, in the order the kernel reads them, so every pointer steps by 8.
  - The model is stored on the host in that order once; nothing is rearranged per token.

## Launch plan

`test/gpt2/schedule.py` lists every launch.

- **Decode:** up to 10 blocks of K = 768 per launch.
- **Prefill:** up to 9 blocks per launch, 8 tokens at a time.
- **FC2:** K = 3,072 runs as four K = 768 launches whose partial sums the host adds, so all four tiles stay busy.
- **Attention:** scores are K = 64 blocks of 8 positions per head, and attention × V is K = context (rounded up to 8) with 8 blocks per head. Up to 31 blocks per launch, the thread-count limit.
- **LM head:** a decode launch over the 50,257-word vocabulary, for the last token only.

## Measurements

- **Cycles.** Launches of real GPT-2 operands run through the RTL chip's pins (`make test_gpt2_bench NUMBER_FORMAT=<0|1|2> GPT2_LAUNCHES=...`).
  - Every output is checked bit for bit against the reference.
  - The host answers each bus beat on the next falling edge (`HOST_LATENCY=0`), so counts are deterministic. The sensitivity to a slower host is measured separately.
  - Launch shapes that were not simulated exactly use a per-kernel fit, cycles = a + b × bus beats, over the simulated ones. Its worst residual is reported.
- **Peak clock.** 1 / (20 ns − worst setup slack) over the chip and its tile, from the signoff STA (`signoff/<fmt>/{chip,tile}/final/metrics.json`).
  - At the worst corner (ss, 100 °C, 1.60 V) this is the guaranteed peak clock.
  - At the typical corner the chip's limit is the 4 ns output-delay budget assumed for `bus_req`, not logic.
- **Power.** The signed-off chip and tile netlists run the decode and prefill kernels at gate level (`test/gpt2/power/run_power.sh`).
  - OpenSTA's `report_power` reads the switching activity, with each block's signoff parasitics, at nom_tt_025C_1v80 and 50 MHz.
  - The window is 10,000 cycles inside the K loop, which is where the chip spends its time.
  - Chip power is the top level plus four times tile 0.
  - The padframe's I/O pads are outside the netlists and are not included.
- **Host.** The host's operations are timed in numpy on the machine that ran the benchmark (`test/gpt2/gpt2.py`), and reported as their own line.
