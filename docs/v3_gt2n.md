# Atreides v3 on GT2N (2 nm)

This is the plan for v3: a new core built around four 128 × 128 matrix units, hardened on the GT2N 2 nm predictive PDK in OpenROAD-flow-scripts (ORFS). As in v2, the same core is built in SF16, FP16 and BF16, and every improvement goes into all three.

v3 targets GT2N only. v2 stays the SKY130 ChipFoundry OpenFrame build on `cf-openframe-v2`. There is no v3 at 130 nm and no double-wide OpenFrame build.

Nothing here is RTL yet. Studies S1 and S2 below come first, because their results set the accumulator format and show whether the performance target is reachable.

## Decisions

| Question | Decision |
|---|---|
| Matrix units | Four 128 × 128 per core (65,536 MACs), weight-stationary |
| Instruction width | 32-bit |
| Data and compute | SF16 in every buffer, register and vector lane |
| Special functions (exp, rsqrt, divide) | None in hardware; the compiler lowers them to vector ops |
| Core organization | One scalar control core, a 128-lane vector unit, four matrix units and DMA; the 8-thread SIMT design goes |
| Accumulator | SF16-compatible. Proposed: SF32 (Q9.23) inside the matrix units only, pending S1 and S2 |
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

FP16 and BF16 get the same core: the same matrix-unit geometry, buffers, ISA and flow settings. Their matrix units accumulate in FP32, as production FP16/BF16 units do, with native-precision accumulation measured as the cheaper alternative. Their vector units compute in their own format.

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

GT2N has no parasitic-extraction rules for OpenRCX, so these use estimated parasitics in every format. On these numbers SF16 clears 2× only on energy against FP16. The accumulator is where the gap can widen: an FP32 accumulator needs alignment and normalization shifters about as large as the multiplier, and SF32 needs none. S2 measures whether that is enough. If it is not, we report the ratios we measure rather than the target.

At 2.0 GHz, one core's 65,536 MACs give 131 TMAC/s.

## Studies before RTL

**S1. Numerics (CPU, no GPU spend).** GPT-2 small in Python bit-level emulation, with matmuls tiled the way the matrix units do them: 128-row K chunks summed across chunks in the accumulator, then one pop.
- Cases: SF16 with the v2 saturating 16-bit accumulator; SF16 with SF32; FP16 and BF16 each with native and with FP32 accumulation; FP32 as the reference.
- Measures: perplexity, top-1 agreement with FP32, maximum logit error.
- Decision rule, the same for every format: use the cheapest accumulator whose perplexity is within 1% of the FP32 reference.

**S2. PE synthesis at SKY130 and GT2N.** Six PEs: SF16 into SF16 (v2) and into SF32; FP16 into FP16 (v2) and into FP32; BF16 into BF16 (v2) and into FP32.
- Synthesis plus a placed and routed 16 × 16 PE block per case at GT2N, so wiring counts.
- Measures: area per MAC, energy per MAC at a fixed clock, maximum clock.
- Gate: if S1's chosen accumulators leave SF16 short of 2× against BF16, say so before writing RTL.

**S3. Matrix-unit hardening at GT2N.** After the RTL exists, harden one 128 × 128 unit per format. A v2 tile's detailed route needed 52–73 GB, and 128 GB is RunPod's largest CPU pod, so a flat 16,384-PE route will not fit. The unit is built hierarchically, from 32 × 32 PE macros.

**S4. Buffer sizing and memories.** Size the unified, weight and accumulator buffers from the GPT-2 and YOLOv8n schedules. GT2N has no SRAM compiler: v2 used flip-flop RAM32 blocks. Check whether ORFS's GT2N platform ships memory macros; if it does not, any SRAM figures are modeled, and will be labeled that way.

## GT2N flow notes (from the v2 runs)

- ORFS Docker image `openroad/orfs:latest`, platform `gt2n`.
- Typical corner only: 0.7 V, 25 °C. Time unit is ps.
- No latch or adder cells in the library; backside power delivery.
- `MAX_ROUTING_LAYER` must be set per design (the floorplan fails without it); v2 used M10.
- Detailed routing needs 52–73 GB per v2 tile, so routes run one at a time on a 128 GB pod.
- DRC and LVS decks are ICV-only, and OpenRCX has no rules. GT2N results are therefore routed with zero DRT violations, not signed off as on SKY130.
- RunPod: 32 vCPU / 128 GB is the largest CPU pod. The REST API needs a User-Agent header.

## Milestones

1. S1 and S2; fix the accumulator per format.
2. Freeze the ISA; assembler, and the compiler's exp/rsqrt/GELU lowering.
3. RTL in all three formats: matrix unit, vector unit, scalar core, DMA, issue queues.
4. Cocotb tests per unit and per format, then GPT-2 and YOLOv8n end to end against the Python reference.
5. S3 and S4: harden the matrix unit, then the core, at GT2N.
6. Benchmarks against FP16 and BF16 (prefill, decode, YOLO), then the docs.
