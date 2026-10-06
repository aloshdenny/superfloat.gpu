# Atreides v3 on GT2N (2 nm)

This is the plan for v3: a new core built around four 128 × 128 matrix units, hardened on the GT2N 2 nm predictive PDK in OpenROAD-flow-scripts (ORFS). As in v2, the same core is built in SF16, FP16 and BF16, and every improvement goes into all three.

v3 targets GT2N only. v2 stays the SKY130 ChipFoundry OpenFrame build on `cf-openframe-v2`. There is no v3 at 130 nm and no double-wide OpenFrame build.

Studies S1 (numerics) and S2 (PE cost) are done; their results are below. They set the accumulator and show how far SF16 is ahead at the PE level. The rest of the core is not RTL yet.

## Decisions

| Question | Decision |
|---|---|
| Matrix units | Four 128 × 128 per core (65,536 MACs), weight-stationary |
| Instruction width | 32-bit |
| Data and compute | SF16 in every buffer, register and vector lane |
| Special functions (exp, rsqrt, divide) | None in hardware; the compiler lowers them to vector ops |
| Core organization | One scalar control core, a 128-lane vector unit, four matrix units and DMA; the 8-thread SIMT design goes |
| Accumulator | SF24 (Q5.19) or SF32 (Q9.23) inside the matrix units only; S1 rules out the v2 16-bit accumulator (see S1) |
| Target | SF16 at least 2–2.5× ahead of FP16 and BF16 on every metric |

Why four 128 × 128 units rather than one 256 × 256: a 256-wide array runs partly empty on layers narrower than 256, and GPT-2's attention heads are 64 wide while YOLOv8n's layers have 16–256 channels. Google moved from TPU v1's single 256 × 256 array to four 128 × 128 units per core for the same reason. GPT-2's 768-wide matrices also tile evenly into 128-wide blocks.

Why drop the SIMT threads: in the v2 SF16 tile at SKY130, the 8 × 8 array is 0.161 mm² of the tile's 1.003 mm² (synthesis). The other 84% is per-tile control for 64 MACs, and eight threads cannot feed 128-row arrays.

## Architecture

```
            external memory
                  |
                 DMA ----------------------+
                  |                        |
   +--------------+---------------+   weight buffer
   |        unified buffer        |        |
   |   (SF16 rows, 128 lanes)     |   +----+----+----+----+
   +---+----------------------+---+   |MXU0|MXU1|MXU2|MXU3|  128 x 128 each
       |                      |       +----+----+----+----+
  vector unit            activations ->  rows stream in
  (128 SF16 lanes)            ^              |
       ^                      +--- POP <-- accumulators (SF32)
       |
  scalar control core: fetches every instruction, issues to the
  DMA, matrix and vector queues; SYNC waits on them
```

- **Scalar core:** in-order, 32 × 32-bit integer registers. It runs loops and addressing, and issues the vector, matrix and DMA instructions into per-unit queues, so they overlap.
- **Vector unit:** 128 SF16 lanes, 32 vector registers of 128 lanes (8 KB), 4 mask registers. It runs everything that is not a matmul: softmax, LayerNorm, GELU, residual adds, bias and requantization.
- **Matrix units:** each PE holds an active and a shadow weight, so the next 128 × 128 weight tile loads while the current one computes. Activation rows stream in from the unified buffer; partial sums go to that unit's accumulator rows.
- **Unified buffer:** activations, as rows of 128 SF16 (256 B).
- **Weight buffer:** stages weight tiles from DMA to the matrix units.
- **Accumulators:** per matrix unit, rows of 128 SF32 (512 B). `MXU.POP` rounds and saturates them to SF16 into the unified buffer.
- **DMA:** moves data between external memory and the unified or weight buffer, with strides set in configuration registers.

Buffer sizes are set in S4 from the GPT-2 and YOLOv8n schedules.

## Numerics

SF16 is Q1.15 sign-magnitude, range (−1, 1), as in v2.

**Accumulator.** Today each product is truncated to 15 bits and added into a 16-bit saturating accumulator. GPT-2's MLP output layer sums 3,072 products per output, so rounding errors build up and any partial sum past ±1 clips. The proposed SF32 accumulator:
- keeps each product to 23 fraction bits;
- holds sums in 32-bit fixed point with 8 guard bits (Q9.23), enough for any 128-row column and for summing K tiles without overflow;
- rounds and saturates once, when results leave the array, after a right shift given per `MXU.POP`, which sets each layer's output scale.

Its cost is a wider integer adder and 16 more flip-flops per PE. SF16 is fixed-point, so the adder needs no alignment or normalization shifter, which an FP32 accumulator does. That difference is the main lever for widening SF16's lead (see Target).

**Scaling.** Values outside (−1, 1) are carried with a per-tensor or per-row power-of-two scale that the compiler tracks, applied with `VSHL`/`VSHR` and the `MXU.POP` shift. S1 checks this on GPT-2's LayerNorm outputs, which have unit variance.

**Lowered functions** (about 20 vector ops per element; softmax, LayerNorm and GELU are around 0.1% of GPT-2's work next to the matmuls):
- **exp:** split x into k·ln2 + r, form 2^k with a shift, then a degree-3 or 4 polynomial in r. Softmax subtracts the row maximum first, so every input is ≤ 0 and every result lies in (0, 1], which fits Q1.15.
- **rsqrt and 1/x:** a first guess from `VCLZ`, then 2–3 Newton steps with `VMAC`.
- **GELU and SiLU:** polynomials, or built on exp.

## Instruction set

All instructions are 32 bits. The scalar subset is RV32I with Zicsr, so the compiler can use an existing RISC-V backend for control code. The vector, matrix, DMA and sync instructions use the four RISC-V custom opcodes. Fields sit where RISC-V puts them: opcode[6:0], rd[11:7], funct3[14:12], rs1[19:15], rs2[24:20], funct7[31:25].

| Opcode | Class | Instructions |
|---|---|---|
| RV32I | Scalar | integer ALU, branches, jumps, scalar loads and stores |
| Zicsr | Configuration | DMA strides, rounding mode, unit status |
| custom-0 (0x0B) | Vector ALU | `VADD`, `VSUB`, `VMUL`, `VMAC`, `VMAX`, `VMIN`, `VCMP.LT`/`VCMP.EQ` (to a mask), `VSEL`, `VSHL`/`VSHR`, `VCLZ`, `VRED.SUM`/`VRED.MAX`, `VPERM`, `VMV.X.S`/`VMV.V.X` |
| custom-1 (0x2B) | Vector memory | `VLD`, `VST`: one 128-lane row of the unified buffer, address x[rs1] + imm |
| custom-2 (0x5B) | Matrix | `MXU.LW`, `MXU.MM`, `MXU.POP` |
| custom-3 (0x7B) | DMA, sync | `DMA.LD`, `DMA.ST`, `SYNC`, `FENCE` |

Vector ALU instructions are R-type, with vd, vs1 and vs2 in the rd, rs1 and rs2 fields; funct7 selects the operation, and a `.X` form takes a scalar register as vs2, broadcast to every lane. Arithmetic is SF16, saturating.

Matrix and DMA instructions take three register operands; the rd field names a third source register:

| Instruction | Operands | Meaning |
|---|---|---|
| `MXU.LW m, xW` | funct3[1:0] = unit | Load the 128 × 128 tile at weight-buffer address x[W] into unit m's shadow weights |
| `MXU.MM m, xA, xC, xN` | funct7[0] = accumulate | Stream x[N] rows from unified-buffer row x[A] through unit m's active weights into accumulator rows from x[C], overwriting or adding |
| `MXU.POP m, xC, xA, xN` | funct7 = shift | Shift x[N] accumulator rows right, round, saturate to SF16 and write them to unified-buffer rows from x[A] |
| `DMA.LD/ST xE, xL, xN` | funct3 = buffer | Copy x[N] bytes between external address x[E] and unified- or weight-buffer address x[L] |
| `SYNC imm` | | Wait until every unit in the mask (DMA, MXU0–3, vector) has drained its queue |
| `FENCE` | | Order external-memory accesses |

The first instruction after `MXU.LW` that uses the new weights swaps them in.

Removed from v2: the per-thread `SYS load` / `SYS compute` / `SYS read`, the SIMT thread masks and branch divergence, and the 16-bit encoding.

## Same core in three formats

FP16 and BF16 get the same core: the same matrix-unit geometry, buffers, ISA and flow settings. Their matrix units accumulate in FP24, the cheapest accumulator that passes S1 for both (native accumulation does not); FP32 was measured too. Their vector units compute in their own format.

## Target: 2–2.5× ahead

With 65,536 MACs per core the PEs dominate the area, so chip-level ratios approach PE-level ratios. Measured at SKY130 (v2 PEs, each with its native-width accumulator):

| SF16 ahead by | vs FP16 | vs BF16 |
|---|---|---|
| Area | 1.35× | 1.09× |
| Power | 2.19× | 1.51× |
| Clock | 1.32× | 1.34× |

The v2 tile at GT2N, before those runs were deleted on 2026-10-05:

| v2 core tile, GT2N, typical corner | SF16 | FP16 | BF16 |
|---|---|---|---|
| 650 ps target, routed: max clock | 1.55 GHz | 1.56 GHz | 1.55 GHz (global route) |
| Power at that clock | 27.0 mW | 43.6 mW | 39.8 mW (global route) |
| Die area | 18,522 µm² | 24,866 µm² | not reached |
| Flip-flops | 11,495 | 19,024 | not reached |
| 500 ps target, 55% utilization, global route: max clock | 2.00 GHz | not reached | 1.94 GHz |
| Power at that clock | 35.2 mW | not reached | 49.9 mW |

GT2N has no parasitic-extraction rules for OpenRCX, so these use estimated parasitics in every format. On these numbers SF16 clears 2× only on energy against FP16. The accumulator is where the gap can widen: an FP32 accumulator needs alignment and normalization shifters about as large as the multiplier, and SF32 needs none. S2 measured that this is not enough on every metric: SF16 is 2.16× ahead of FP16 on energy, but 1.3–1.6× ahead of BF16 and level on clock (S2 below).

At 2.0 GHz, one core's 65,536 MACs give 131 TMAC/s.

## Study S1: accumulator numerics

GPT-2 small on the WikiText-2 test set: 32 windows of 1,024 tokens (32,736 next-token predictions), spread evenly over the set. Every matmul runs through an emulated matrix unit (`v3/s1/mxu_emu.py`): operands quantized to the 16-bit format, products accumulated along K in order as a column does, one rounding to the 16-bit format at the pop. Everything else stays FP32, so only the matrix unit changes. The emulation is bit-exact against the RTL's reference arithmetic (`v3/s1/check_kernels.py`). Run on a RunPod 32-vCPU pod.

| Format, accumulator | Perplexity | vs FP32 | Top-1 agreement with FP32 |
|---|---|---|---|
| FP32 reference | 29.133 | | |
| SF16, v2 16-bit saturating (4 windows; FP32 27.78) | 196.9 | +609% | 36.3% |
| SF16, 16-bit with oracle headroom (4 windows) | 117.5 | +323% | 45.2% |
| SF16, SF24 (Q5.19) | 29.423 | +0.996% | 96.1% |
| SF16, SF32 (Q9.23) | 29.161 | +0.10% | 98.8% |
| FP16, native FP16 (v2) | 30.048 | +3.14% | 86.0% |
| FP16, FP24 (1/8/15) | 29.143 | +0.03% | 98.4% |
| FP16, FP32 | 29.138 | +0.02% | 98.5% |
| BF16, native BF16 (v2) | 129.3 | +344% | 39.3% |
| BF16, FP24 | 29.342 | +0.72% | 89.4% |
| BF16, FP32 | 29.355 | +0.76% | 89.6% |
| SF16, SF24, truncated product | 29.294 | +0.55% | 97.3% |
| SF16, SF28 (Q5.23) | 29.161 | +0.10% | 98.8% |
| SF16, SF28 or SF32, truncated product | 29.153 | +0.07% | 98.9% |
| FP16, FP24, truncated product | 29.140 | +0.02% | 98.4% |

- **The v2 SF16 PE cannot run GPT-2's matmuls.** Each product is truncated to Q1.15, and with one scale per tensor most activations and weights sit far below full scale, so small products lose most of their bits. Headroom does not help: with no clipping at all, perplexity is still +323%.
- **Under the 1% rule:** SF16 takes SF24 (by 0.004 points), FP16 and BF16 take FP24. SF32 is the safe SF16 choice: its 98.8% top-1 agreement matches FP16 with FP24 or FP32.
- **BF16's 8-bit significand caps top-1 agreement at about 89%,** whatever the accumulator.

## Study S2: PE cost at GT2N

Each variant is an 8 × 8 block of v3 PEs (`v3/pe/`) with registered edges, taken through ORFS on GT2N to global routing: synthesis, floorplan, placement, clock tree, global route. GT2N has no extraction rules, so timing and power use the global route's estimated parasitics; detailed routing would not change them.
- **Checks:** every PE is bit-exact against Python models (`v3/pe/check_block.py`, 8,000 outputs per variant), and every block's gate-level netlist matches its RTL on the power stimulus.
- **Power:** gate-level switching activity at 2 GHz on real GPT-2 operands (layer 5's MLP input, 1,024 tokens, four 8 × 8 weight tiles from its weights, true partial sums from the north).
- **Maximum clock:** from a 300 ps run, 1 / (300 ps − register-to-register slack).
- **Per MAC:** the block's figure / 64, edge registers included.

Stages are the register stages on the partial-sum path through one PE (the array skews each row by that many cycles); FP blocks marked (a) register the alignment.

| Variant | Stages | Meets 2 GHz | Area/MAC (µm²) | Energy/MAC (fJ) | Max clock (GHz) | SKY130 synthesis area/MAC (µm²) |
|---|---|---|---|---|---|---|
| SF16, 16-bit (v2) | 1 | yes | 68.8 | 278 | 2.64 | 10,107 |
| SF16, SF24 | 1 | yes | 75.0 | 314 | 2.53 | 10,798 |
| SF16, SF32 | 1 | yes | 82.9 | 350 | 2.51 | 11,434 |
| FP16, native | 2 | no | 104.0 | 566 | 2.14 | 12,206 |
| FP16, FP24 | 2 | no | 116.1 | 630 | 2.03 | 13,086 |
| FP16, FP32 | 2 | no | 124.6 | 708 | 2.00 | 14,295 |
| FP16, native (a) | 3 | yes | 112.5 | 630 | 2.70 | 13,503 |
| FP16, FP24 (a) | 3 | yes | 122.0 | 678 | 2.46 | 14,471 |
| FP16, FP32 (a) | 3 | yes | 131.3 | 726 | 2.48 | 15,482 |
| BF16, native | 2 | no | 86.1 | 435 | 2.17 | 9,950 |
| BF16, FP24 | 2 | no | 91.3 | 473 | 2.26 | 10,642 |
| BF16, FP32 | 2 | no | 113.1 | 610 | 2.06 | 12,578 |
| BF16, native (a) | 3 | yes | 95.4 | 491 | 3.02 | 10,968 |
| BF16, FP24 (a) | 3 | yes | 98.0 | 516 | 2.77 | 11,497 |
| BF16, FP32 (a) | 3 | yes | 119.3 | 657 | 2.69 | 13,835 |

Area and energy of a block that misses 2 GHz are for reference only. The SKY130 column is synthesis area (Yosys/ABC, 10 ns) with no timing.

**At 2 GHz, each format's cheapest variant that meets the clock and S1's rule:**

| | SF16, SF24 | FP16, FP24 (a) | BF16, FP24 (a) | SF16 vs FP16 | SF16 vs BF16 |
|---|---|---|---|---|---|
| Area/MAC | 75.0 µm² | 122.0 µm² | 98.0 µm² | 1.63× | 1.31× |
| Energy/MAC | 314 fJ | 678 fJ | 516 fJ | 2.16× | 1.64× |
| Max clock | 2.53 GHz | 2.46 GHz | 2.77 GHz | 1.03× | 0.91× |
| Partial-sum stages per row | 1 | 3 | 3 | 3× fewer | 3× fewer |

With SF32 instead (the quality match for FP16): 1.47× area, 1.94× energy and 1.02× clock against FP16; 1.18×, 1.47× and 0.90× against BF16.

- **2× is reached on energy against FP16 only.** Against BF16, SF16 is 1.3× smaller and 1.6× more efficient, and BF16 clocks 9% higher once it has two more pipeline stages.
- **Where SF16 wins and loses:** its fixed-point accumulator needs no alignment or normalization, so one stage meets 2 GHz where FP needs three. Its cost is the 15 × 15 magnitude multiplier, against BF16's 8 × 8.
- **The fewer stages matter for latency:** a 128-row column fills in 128 cycles for SF16 against 384 for FP. That counts most in batch-1 decode, where each matmul pass is short.

## Levers: truncated product and clock gating

Both measured as S2 was, on a second pod, with S1's GPT-2 run for every variant that changes the arithmetic. Every block is bit-exact against its Python model and its gate-level netlist matches the RTL.
- **Truncated product.** The PE keeps 19 (SF24) or 23 (SF28, SF32) of the product's 30 fraction bits, so its lowest columns only feed carries. The product is written as its partial-product rows with the columns below K left out, plus COMP, their expected value with random bits: SF24 K 9, COMP 1,024; SF28 and SF32 K 6, COMP 80. COMP stays below the kept LSB, so a zero operand still gives zero.
  - FP16 gets the same on its 11 × 11 significands: K 4, COMP 12; FP24 keeps 16 of the product's 22 bits.
  - BF16's 8 × 8 product is narrower than FP24's significand, so there is nothing to drop.
  - COMP also cancels the truncation's bias toward zero: SF24 improves from +0.996% to +0.55% perplexity.
- **Clock gating** of both weight registers, in every format. GT2N has no clock-gate cell or latch, so a gate is a falling-edge flop holding the enable, ANDed with the clock (cycle-identical). Synthesis merges the per-row gates into one per register, and the clock tree is built under each.
- **SF28 (Q5.23).** S1 never clipped SF24's Q5 integer range, so SF28 has SF32's precision with four fewer bits.

| Variant at 2 GHz | Area/MAC (µm²) | Energy/MAC (fJ) | TFLOPS/mm² | TFLOPS/W | Max clock (GHz) |
|---|---|---|---|---|---|
| SF16, SF24 | 75.0 | 314 | 53.4 | 6.36 | 2.53 |
| SF16, SF24, rows (none dropped) | 74.6 | 317 | 53.6 | 6.30 | 2.81 |
| SF16, SF24, truncated | 67.8 | 275 | 59.0 | 7.26 | 2.86 |
| **SF16, SF24, truncated + gated** | **66.5** | **233** | **60.1** | **8.60** | 2.62 |
| SF16, SF28 | 80.0 | 340 | 50.0 | 5.87 | 2.52 |
| SF16, SF28, truncated | 77.2 | 331 | 51.8 | 6.04 | 2.66 |
| **SF16, SF28, truncated + gated** | **75.8** | **294** | **52.8** | **6.80** | 2.70 |
| SF16, SF32, truncated + gated | 78.4 | 304 | 51.0 | 6.57 | 2.75 |
| FP16, FP24 (a) | 122.0 | 678 | 32.8 | 2.95 | 2.46 |
| FP16, FP24 (a), truncated | 113.6 | 624 | 35.2 | 3.21 | 2.81 |
| **FP16, FP24 (a), truncated + gated** | **113.0** | **589** | **35.4** | **3.40** | 2.82 |
| BF16, FP24 (a) | 98.0 | 516 | 40.8 | 3.87 | 2.77 |
| **BF16, FP24 (a), gated** | **98.2** | **487** | **40.7** | **4.11** | 2.87 |

TFLOPS/mm² is 2 FLOPs per MAC per cycle at 2 GHz over the area per MAC; TFLOPS/W is 2 FLOPs over the energy per MAC.

**Compute with every lever, SF16 ahead by:**

| | vs FP16 | vs BF16 |
|---|---|---|
| SF24, TFLOPS/mm² | 1.70× | 1.48× |
| SF24, TFLOPS/W | 2.53× | 2.09× |
| SF28 (quality of FP16), TFLOPS/mm² | 1.49× | 1.30× |
| SF28, TFLOPS/W | 2.00× | 1.65× |
| Max clock (SF24) | 0.93× | 0.91× |

- **Compute per watt clears 2× against both** with SF24, and against FP16 with SF28.
- **Compute per mm² does not:** SF24 is 1.70× FP16 and 1.48× BF16.
- **Max clock:** FP and BF16 clock higher only with two more pipeline stages; at equal stages SF16 is faster (S2).
- **The truncated product is worth 9.6% of SF24's area and 12% of its energy,** and the rows form alone is not where the saving comes from (74.6 µm² vs 75.0). Clock gating takes another 15% of SF24's energy and 5–6% of the FP formats'.

## Workloads on a 2 nm die (modeled)

`v3/perf/v3_perf.py` (run on the research server) puts the measured PEs on an 800 mm² die: 70 mm² of matrix units in every format (SF16 64, FP16 37, BF16 43 units of 128 × 128), 14 mm² of cores, 40 mm² of I/O, and the rest SRAM at 38.1 Mb/mm², 3.22 GB in every format, with 4 HBM3E stacks for overflow. It is a roofline over the matrix units (128 × 128 tiles, 128 cycles to load a tile, fill latency per GEMM), the vector units (software exp/GELU/softmax/SiLU), HBM and a 700 W cap, on GPT-2 small to XL and YOLOv8 n to x. `v3/perf/update_doc.py` writes the results into the shuttle-plan document's section 6.
- **With the plan's 16 × 128 vector lanes,** every large prompt and image batch is vector-bound. The matrix units are 2–32% busy, and SF16 trails by 8–12% (its scale ops).
- **With 65,536 lanes,** prompts and batches become matrix-bound. SF16 leads FP16 by 1.40–1.83× and BF16 by 1.36–1.57× on GPT-2 prompts, and 1.33–1.89× and 1.26–1.71× on YOLOv8 batches.
- **Batch-1 decode is set by the 128-cycle weight load per tile.** SF16 leads 1.66–1.72× (more units, 1 stage vs 3), and 4 rows per cycle would give 1.86×.
- **GPT-2 XL's weights take the SRAM,** so its KV cache goes to HBM and batch decode ties at about 15,500 tokens/s.

## GT2N flow notes (from the v2 runs)

- ORFS Docker image `openroad/orfs:latest`, platform `gt2n`.
- Typical corner only: 0.7 V, 25 °C. Time unit is ps.
- No latch or adder cells in the library; backside power delivery.
- `MAX_ROUTING_LAYER` must be set per design (the floorplan fails without it); v2 used M10.
- Detailed routing needs 52–73 GB per v2 tile, so routes run one at a time on a 128 GB pod.
- DRC and LVS decks are ICV-only, and OpenRCX has no rules. GT2N results are therefore routed with zero DRT violations, not signed off as on SKY130.
- RunPod: 32 vCPU / 128 GB is the largest CPU pod. The REST API needs a User-Agent header.

## Milestones

1. S1, S2 and the levers (done): SF16 SF24 or SF28 with a truncated product, FP16 FP24 truncated, BF16 FP24; weight-register clock gating in all three.
2. Freeze the ISA; assembler, and the compiler's exp/rsqrt/GELU lowering.
3. RTL in all three formats: matrix unit, vector unit, scalar core, DMA, issue queues.
4. Cocotb tests per unit and per format, then GPT-2 and YOLOv8n end to end against the Python reference.
5. S3 and S4: harden the matrix unit, then the core, at GT2N.
6. Benchmarks against FP16 and BF16 (prefill, decode, YOLO), then the docs.
