# Systolic PE optimisation study (Sky130 HD)

This study compares three versions of the weight-stationary SF16 processing element (`systolic_pe`): the original, a lean rewrite that is now in `src/systolic_pe.sv`, and a version with a deeper-pipelined multiplier. It also measures a truncated multiplier as an option that was not adopted. The PE is the unit most worth optimising: the OpenFrame chip has 256 of them (64 per tile), and they make up most of each tile's area.

All numbers below come from hardened layouts, not estimates. Each PE was hardened with LibreLane using the same configuration (`librelane/systolic_pe/config.json`, 160 × 200 µm die), except for the clock period and whether the Booth multiplier was used, which are noted per row.

## Variants

| Variant | Description |
|---|---|
| Original | Separate `b_out` shift register that moves on every enabled cycle; weight register loaded on `load_weight`; per-PE `enable` on every register; per-PE negative-zero canonicalisation of both inputs; per-PE sign-magnitude output conversion. 3-stage MAC. |
| **Lean (adopted)** | The weight register is also the southward weight chain and shifts only on `load_weight`. The activation register, product register and valid pipe run freely; only the accumulator is gated. Canonicalisation moves to the array edge; the raw two's-complement accumulator is output and the core converts the one cell it reads. 3-stage MAC. |
| Pipelined | The lean PE with the 15 × 15 multiplier split into two registered partial products (15 × 7 and 15 × 8), summed in the next stage. 4-stage MAC, one cycle more latency. |
| Truncated (option) | The lean PE with the partial-product bits below column K dropped and replaced by their expected value. Not bit-exact. |

## Results

| | Original | **Lean** | Pipelined |
|---|---|---|---|
| Std-cell area at 20 ns | 18,147.4 µm² | **16,610.9 µm² (−8.5%)** | 18,554.0 µm² (+2.2%) |
| Flip-flops | 82 | **66** | 105 |
| Setup slack at 20 ns, worst corner (max_ss_100C_1v60) | +6.726 ns | **+7.311 ns** | +8.324 ns |
| Fmax at max_ss, from a tight-clock harden | 88.4 MHz (10 ns target) | **92.2 MHz** (10 ns target) | 105.1 MHz (6 ns target) |
| Fmax at nom_tt, same runs | 166.9 MHz | **175.5 MHz** | 198.7 MHz |
| Worst hold slack at 20 ns | −0.003 ns (max_ff) | **+0.047 ns** | +0.055 ns |
| Power, full-rate MAC stream, 50 MHz, nom_tt | 1.24 mW | **1.16 mW (−6.5%)** | 1.25 mW (+0.8%) |
| Magic/KLayout DRC, LVS, antenna, slew, cap | 0 | 0 | 0 |

**Notes on the table:**
- The original and lean PEs use the Booth multiplier. The pipelined PE does not, because it synthesised smaller without it (15,800 vs 16,425 µm²).
- Each run reports one max-fanout violation. It is the clock-tree root buffer (`clkbuf_0_clk`, fanout 16 against a limit of 8), set by the PE harden configuration's clock-tree settings. It is identical in every run.
- Fmax is 1 / (T − WS), taken from the run whose target clock period T was tighter than the design could meet.

**Power method:**
1. The routed netlist of each 20 ns harden was simulated with the Sky130 cell models under the same stimulus: one weight load, then a compute with a fresh random activation every cycle for 5,000 cycles, with a clear every 64 cycles.
2. OpenSTA computed power from that switching activity and the extracted nominal parasitics. Activity was annotated on 100% of pins in every case.

### Truncated multiplier (measured, not adopted)

| Variant | Synthesised area | Products bit-exact | Error range | Mean error |
|---|---|---|---|---|
| Lean, exact | 13,888.3 µm² | 100% | 0 | 0 |
| Truncated, K = 8 | 13,306.5 µm² | 99.41% | ±1 LSB | −0.002 LSB |
| Truncated, K = 10 | 12,359.4 µm² | 97.17% | ±1 LSB | +0.008 LSB |
| Truncated, K = 12 | 11,352.1 µm² | 87.89% | ±1 LSB | −0.031 LSB |

- Error is against exact SF16 floor-truncation, over 400,000 random operand pairs. One LSB is 2⁻¹⁵ ≈ 3.05 × 10⁻⁵.
- Truncation would change the arithmetic that SF16 defines, so the chip keeps the exact multiplier.

## Findings

1. **The lean PE is better on every measure and is bit-exact.** It is 8.5% smaller, uses 6.5% less power at full rate, has 4% higher Fmax, and removes the original's small hold violation. It was proven equivalent in several ways:
   - a 200,000-cycle randomised lockstep simulation against the original (`librelane/pe_study/tb_eq.sv`)
   - the array unit and stress suites
   - the ISA-level 8 × 8 kernel on all four tiles
   - the chip-level pin tests
2. **Deeper pipelining does not pay on this chip.**
   - The split multiplier raises max_ss Fmax by 14%, but costs 11.7% area and 7.8% power relative to the lean PE.
   - More importantly, the chip clock is set by the core's control and datapath at about 50 MHz, not by the PE. The PE already has +7.3 ns of slack at 20 ns.
   - A faster PE only helps if the core pipeline is also reworked.
3. **Across the chip**, the lean PE saves about 256 × 1,536 µm² ≈ 0.39 mm² of PE area and about 20 mW at full MAC rate.

## FP16 and BF16 PEs

The FP16 and BF16 chip variants use `fp_systolic_pe` (`src/fp_systolic_pe.sv`), a lean-contract PE with a fused multiply-add (one rounding, round to nearest even, flush to zero). BF16 uses its 4-stage pipeline: operand, multiply, align+add, round. FP16 sets `ALIGN_STAGE`, which registers the aligned operands between align and add (5 stages). The accumulator loop spans two cycles (BF16) or three (FP16); the core issues SYS computes at least six cycles apart.

The FP PEs were hardened with the same LibreLane settings as the SF16 lean PE, on a 200 × 220 µm die because they are larger.

Power uses one stimulus for all three PEs (`librelane/pe_study/tb_power_fp.sv`):
- one weight load (≈ 0.337)
- then a compute every second cycle, each with a fresh random activation
- a clear every 64 computes
- activations: SF16 |a| < 0.25; FP16/BF16 |a| in [0.125, 2)

The SF16 row re-measures the lean PE's 20 ns layout from the table above under this stimulus.

| | SF16 (lean) | FP16 | BF16 |
|---|---|---|---|
| Std-cell area at 20 ns | 16,610.9 µm² | 21,774.6 µm² (+31%) | 18,161.2 µm² (+9%) |
| Flip-flops | 66 | 121 | 115 |
| Setup slack at 20 ns, max_ss_100C_1v60 | +7.311 ns | +1.753 ns | +2.533 ns |
| Fmax at max_ss, from a 10 ns harden | 92.2 MHz | 69.9 MHz | 68.6 MHz |
| Fmax at nom_tt, same runs | 175.5 MHz | 133.4 MHz | 129.7 MHz |
| Worst hold slack at 20 ns | +0.047 ns | +0.107 ns | +0.062 ns |
| Power, compute every 2nd cycle, 50 MHz, nom_tt | 0.782 mW | 1.330 mW (1.7×) | 1.180 mW (1.5×) |
| Magic/KLayout DRC, LVS, antenna | 0 | 0 | 0 |
| Max slew / cap at signoff | 0 | 8 / 1 | 0 |

- **Critical path:** the FP PEs are limited by the align+add stage, not the multiplier. The exponent compare, the alignment shift with sticky, and the 2M+4-bit add or subtract happen in one cycle.
- **Where the extra power goes:** sequential and clock power is 62% of the FP16 total and 68% of BF16, against 44% for SF16. The FP PEs carry nearly twice the pipeline state: product, exponent and flag registers, plus a sum register one adder-window wide.
- **Pipeline depth:**
  - A 5-stage version (align and add in separate cycles) had more slack: FP16 +6.862 ns, BF16 +5.902 ns.
  - But it cost 183/168 flops, 22,469/18,883 µm² and 1.710/1.500 mW (FP16/BF16).
  - An earlier 5-stage FP16 tile reached 0.57 utilisation and could not place its antenna diodes (DPL-0036), so the 4-stage PE was tried first.
  - The 4-stage FP16 tile then missed 20 ns at max_ss by 1.95 ns before routing and 3.02 ns after. The failing path is the align+add stage, and in the tile the accumulator also drives the eight threads' result muxes. FP16 therefore uses the 5-stage PE (`ALIGN_STAGE`).
  - The BF16 tile meets timing before routing with the 4-stage PE (+0.27 ns at 0.43 utilisation), and keeps it.
  - With the FP16 PE split, the tile's only paths within 1 ns of 20 ns at max_ss were the eight thread FMAs' align+add, at −0.098 ns before routing. `fp_fma` takes the same `ALIGN_STAGE` register. It fills the FMA's idle first EXECUTE cycle, so no cycles are added.
- **The first 4-stage version** had a slower adder: one shifter per operand, a shifter-based sticky bit, and a zero detect on the sum. It missed 20 ns at max_ss by 0.26 ns (BF16).

## Reproducing

`librelane/pe_study/` contains the variant RTL (`variants/`), the equivalence bench, the power stimulus and STA script, and the metrics extractor.

- **Equivalence:**
  ```bash
  iverilog -g2012 -o eq.vvp tb_eq.sv variants/pe_base.sv variants/pe_pipe.sv ../../src/systolic_pe.sv && vvp eq.vvp
  ```
  Run it from `librelane/pe_study/`. It reports `lean mismatches=0 pipe mismatches=0`.
- **Hardening:** copy `librelane/systolic_pe/config.json`, point `VERILOG_FILES` at a variant, and set `CLOCK_PERIOD`.
- **Power:**
  1. Simulate `tb_power.sv` against the hardened netlist with the Sky130 cell models (`-DFUNCTIONAL -DUNIT_DELAY=#1`; add `-DBASE` for the original PE's port list).
  2. Run `sta -exit power.tcl` with `NL`, `SPEF`, `SDC`, `VCD` and `LIB` set in the environment.
- **FP16/BF16 power:** the same steps with `tb_power_fp.sv` (`-P tb_power_fp.FMT=1` or `2`, or `-DSF16 -P tb_power_fp.FMT=0` for the lean PE) and `power_fp.tcl` (which also needs `TOP`). The FP PEs are hardened from `src/fp_arith.sv` and `src/fp_systolic_pe.sv`, with `SYNTH_PARAMETERS` `EXP_BITS`/`MANT_BITS` = 5/10 (FP16) or 8/7 (BF16).
