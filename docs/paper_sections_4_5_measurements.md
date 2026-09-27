# Atreides / SuperFloat — Sections 4–5 measurement report

**Date:** 2026-07-20  
**Sources:** existing LibreLane run directories only (no new flow invocations for this write-up).  
**Rule:** Numbers are copied or derived from report files cited below. Gaps are called out; README aspirational clocks are not treated as measured.

Machine-readable extract of the hierarchical runs: `docs/hierarchical_run_extract.json`.

---

## Scope of what was hardened

| Level | Run directory | DESIGN_NAME | Notes |
| --- | --- | --- | --- |
| Systolic PE (SF MAC PE) | `librelane/systolic_pe/runs/RUN_2026-07-20_00-16-26` | `systolic_pe` | Closest thing to a standalone “FMA” harden; there is **no** `librelane/fma/` |
| Systolic array | `librelane/systolic_array/runs/RUN_2026-07-20_00-29-07` | `systolic_array` | User-cited path `librelane/core/runs/RUN_2026-07-20_00-40-46` **does not exist**; this is the array run present in-tree |
| Core | `librelane/core/runs/RUN_2026-07-20_09-10-03` | `core` | |
| Full chip (flat TT) | `artifacts/GDS_logs/runs/wokwi` (+ `artifacts/tt_submission/.../metrics.csv`) | `tt_um_aloshdenny_gpu` | Tiny Tapeout submission harden |
| Hierarchical `gpu` macro | — | — | **No** `librelane/gpu/runs/` |
| Standalone `fma` macro | — | — | **Does not exist** in this tree |

All hierarchical configs use `CLOCK_PERIOD: 20.0` (50 MHz target), not the older README-era 5 ns / 6 ns / 8 ns targets.

**Implication for the paper:** Drop any table that lists a measured `fma` macro at 5 ns / 200 MHz unless that run is recovered from elsewhere. Those figures contradict every `CLOCK_PERIOD` and STA clock report in the current tree (all 20 ns). Treat them as outdated config targets or a missing older run — **not** as results from this repository state.

---

# Section 4 — Hardware architecture, timing, critical path

## 4.1 Signoff table (measured)

Corner for WNS/TNS/slack: **`max_ss_100C_1v60`** post-PnR (`57-openroad-stapostpnr`), unless noted.  
Area / util / DRC / LVS / antenna / power from each run’s `final/metrics.csv` (TT: also `artifacts/tt_submission/tt_submission/stats/metrics.csv`).

| Design | Constrained period (ns) | Constrained Fmax (MHz) | WNS (ns) | TNS (ns) | Worst slack (ns) | Implied Fmax† (MHz) | Stdcell area (µm²) | Core area (µm²) | Util | Magic DRC | LVS | Antenna viol. | Power total (W) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `systolic_pe` | 20.0 | 50.0 | 0.0 | 0.0 | 6.726457803363732 | 75.33784013233607 | 18147.4 | 26268.9 | 0.690831 | 0 | 0 | 0 | 0.0027342247776687145 |
| `systolic_array` | 20.0 | 50.0 | 0.0 | 0.0 | 7.62432627501624 | 80.80368165986958 | 85931.2 | 99382.8 | 0.864648 | 0 | 0 | 0 | 0.006961531471461058 |
| `core` | 20.0 | 50.0 | 0.0 | 0.0 | 0.9345005034306447 | 52.45076323229507 | 129971 | 451496 | 0.287868 | 0 | 0 | 0 | 0.01224494632333517 |
| `tt_um_aloshdenny_gpu` (flat) | 20.0 | 50.0 | 0.0 | 0.0 | 3.9543640592375056 | 62.32224161708605 | 378733 | 694446 | 0.545375 | 0 | 0 | 0 | 0.02164887823164463 |

† **Implied Fmax** = \(1000 / (T_{\mathrm{clk}} - S_{\mathrm{worst}})\) using the reported worst *positive* setup slack on the constrained 20 ns clock. This is reproducible from `ws.max.rpt` + `clock.rpt` but is **not** a separate OpenROAD binary-search Fmax. All designs **met** the 20 ns constraint (WNS = 0).

### Raw report paths

| Design | metrics | clock / ws / wns | critical `max.rpt` |
| --- | --- | --- | --- |
| PE | `librelane/systolic_pe/runs/RUN_2026-07-20_00-16-26/final/metrics.csv` | `.../57-openroad-stapostpnr/max_ss_100C_1v60/{clock,ws.max,wns.max}.rpt` | `.../max.rpt` |
| Array | `librelane/systolic_array/runs/RUN_2026-07-20_00-29-07/final/metrics.csv` | same pattern under that run | `.../max.rpt` |
| Core | `librelane/core/runs/RUN_2026-07-20_09-10-03/final/metrics.csv` | same | `.../max.rpt` |
| Flat GPU | `artifacts/GDS_logs/runs/wokwi/final/metrics.csv` | `artifacts/GDS_logs/runs/wokwi/57-openroad-stapostpnr/max_ss_100C_1v60/` | `.../max.rpt` |

Commands used:

```bash
python3 docs/../  # extract script regenerated docs/hierarchical_run_extract.json
# Equivalent one-liners:
sed -n '1,20p' librelane/systolic_pe/runs/RUN_2026-07-20_00-16-26/57-openroad-stapostpnr/max_ss_100C_1v60/clock.rpt
cat librelane/systolic_pe/runs/RUN_2026-07-20_00-16-26/57-openroad-stapostpnr/max_ss_100C_1v60/ws.max.rpt
```

---

## 4.2 Critical-path finding (central for Section 4)

### Flat Tiny Tapeout chip — FMA is **not** the bottleneck

On `tt_um_aloshdenny_gpu`, the worst setup path is **memory-address / control combinational logic**, not a 15×15 multiplier cone.

| Item | Value |
| --- | --- |
| Data arrival | 17.938980 ns |
| Slack | 3.954364 ns (MET) |
| Extract | `docs/sta_critical_path_max_ss.txt` |
| Characteristic | Path involves `data_mem_read_address_flat[...]`; cell mix dominated by `or4`, `a21oi`, `xnor2`, `a21o`, etc. |

**Paper consequence:** The claim “removing exponent alignment shortens the *chip* critical path” is **not supported by this signoff**. On the submitted flat design, shortening the SF MAC would not move Fmax until the address-generation / memory datapath is fixed. That is a positive architectural finding about *where time is spent*, not merely a missing measurement.

### Standalone PE / array — path *does* touch the SF MAC mantissa

At the PE and array hierarchy levels (no external memory arbiter), the worst path **does** pass through PE pipeline mantissa nets:

| Design | Start / end (STA) | Notable net on path | Arrival (ns) | Slack (ns) |
| --- | --- | --- | ---: | ---: |
| `systolic_pe` | `_2622_` → `_2638_` | `r2_mantissa[9]` | 13.905663 | 6.726458 |
| `systolic_array` | `g_row[0].g_col[0].pe/_2676_` → `.../pe/_2705_` | `g_row[0].g_col[0].pe/r2_mantissa[1]` | 13.766011 | 7.624326 |
| `core` | `_19329_` → `_19124_` | flattened; not labeled `r2_mantissa` in the first path header | 20.126719 | 0.934501 |

PE path cell mix (first path, through data arrival): heavy `xnor2_2`, `and2_2`, `or2_2`, `a211o_2` — consistent with SF sign-magnitude / mantissa logic, but **STA does not emit a clean three-bucket split** (sign-XOR+abs | 15×15 mul | accumulate+saturate) with per-stage picoseconds. Those stage delays remain **not separately reportable** from these logs without additional path-group / hierarchical naming work.

**Honest Section 4 framing:**

1. Report the hierarchical PE/array/core/flat-GPU table above (all @ 20 ns).  
2. State that PE/array critical paths lie in the SF MAC PE datapath (`r2_mantissa`), while the **full-chip** critical path does not.  
3. Do **not** claim a measured end-to-end “exponent-alignment removal → chip Fmax uplift” from this tapeout.  
4. Optional PE-level argument: SF PE meets 50 MHz with ~6.7 ns positive slack; that is a *PE* result, not a chip-Fmax result.

---

## 4.3 FP16 baseline and Fmax uplift

| Item | Status |
| --- | --- |
| FP16 FMA (or align+normalize-only) LibreLane harden | **Not in tree** |
| Measured SF/FP16 Fmax ratio | **Unavailable** |
| 1.2–1.7× figure | Keep only as a **literature-derived / analytical estimate**, explicitly labeled — **not** a result of this repo’s STA |

Cycles/op (RTL, not STA):

| Unit | Cycles / throughput |
| --- | --- |
| Scalar SF FMA (`src/fma.sv`) | 2 EXECUTE cycles per op |
| Systolic PE (`src/systolic_pe.sv`) | 1 MAC/cycle steady-state (3-cycle fill to first result) |
| FP16 pipeline depth | N/A (no design) |

---

## 4.4 Power (from existing reports)

| Design | `power__total` (W) from `final/metrics.csv` |
| --- | ---: |
| systolic_pe | 0.0027342247776687145 |
| systolic_array | 0.006961531471461058 |
| core | 0.01224494632333517 |
| tt_um_aloshdenny_gpu | 0.02164887823164463 |

Additional OpenROAD `power.rpt` files exist under each run’s `57-openroad-stapostpnr/<corner>/`. Example flat-GPU `nom_tt_025C_1v80` total: **1.840029e-02 W** (`artifacts/GDS_logs/runs/wokwi/57-openroad-stapostpnr/nom_tt_025C_1v80/power.rpt`).

FP16 power: **N/A**.

---

# Section 5 — Hardware-aware optimizations (measured negative result)

Implementation: `test/test_hw_aware_opts.py`  
Results JSON: `test/logs/hw_aware_opts_results.json`  
Command: `make test_hw_aware_opts` (sim clock 10 ns in `setup_test`; cycle counts are what matter for comparison).

These are **software** mechanisms on the existing ISA (no new opcode, no FMA RTL change). No LibreLane re-harden of a “unity FMA” was performed.

## 5.1 Sparse skip (`CMP` + `BRz` around `FMA`)

### Element-wise magnitude prune — functionally broken under SIMT

When zeros are scattered so different threads disagree on the branch, correctness fails:

| actual sparsity | correct | cycles |
| ---: | --- | ---: |
| 0.5 | **False** | 2650 |

(`sparse_elementwise_brz_divergence_demo` in the JSON.)

### Structured row prune (SIMT-safe) — correct, but **slower** than dense

Zeroing whole rows of B keeps all lanes on the same branch:

| target sparsity | actual | FMA util | dense cycles | sparse-skip cycles | Δ (sparse − dense) |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 0.0 | 0.0 | 1.0 | 2406 | 2730 | **+324** |
| 0.25 | 0.25 | 0.75 | 2406 | 2690 | **+284** |
| 0.50 | 0.50 | 0.50 | 2406 | 2650 | **+244** |
| 0.75 | 0.75 | 0.25 | 2406 | 2610 | **+204** |

**Conclusion:** On this ISA/core, compare-and-branch overhead exceeds the FMA issue cycles saved. The k-loop trip count does not shrink. A credible sparse path needs either:

- a **compacted / CSR-style** kernel that reduces iterations, or  
- a **hardware skip** in the FMA/scheduler (predication / valid mask), not a software `BRz`.

## 5.2 Unity bypass (SF16 `0x7FFF` → `ACT` add instead of `FMA`)

True \(+1.0\) is not representable in SF16; bypass uses max-positive `0x7FFF`.

| unity frac | dense cycles | bypass cycles | Δ (bypass − dense) | bypass correct |
| ---: | ---: | ---: | ---: | --- |
| 0.0 | 2406 | 3174 | **+768** | yes |
| 0.25 | 2406 | 3134 | **+728** | yes |
| 0.50 | 2406 | 3094 | **+688** | yes |
| 0.75 | 2406 | 3054 | **+648** | yes |

Also a **regression** versus dense FMA. RTL area/Fmax cost of a hardware unity mux in the PE: **not measured** (would need a modified PE harden).

## 5.3 Trained-model statistics

| Statistic | Status |
| --- | --- |
| Fraction of weights near ±1 on a real network | **Unsupported** — no usable ResNet-20 / loadable checkpoint in this repo for the measurement |
| Magnitude-prune sparsity on a real ResNet-20 | **Unsupported** — benches used deterministic synthetic matrices |
| Stock `make test_model_resnet` | **FAIL** (`ResNet Conv (MatMul) failed!`) under current slim dual-core TB — cannot report opts-on vs opts-off full-model deltas from that harness |

ResNet-*like* 4×4 matmul step (synthetic, structured 50% sparsity) from the same bench file: dense 2406 vs sparse-skip 2650 cycles (Δ **+244**), both functionally correct.

---

# Recommended Section 4 / 5 prose stance

**Section 4**

- Publish the PE / array / core / flat-GPU table at **20 ns / 50 MHz** with the exact areas and slacks above.  
- Explicitly retire README-style 5 ns–200 MHz macro numbers unless an archived run is produced.  
- Lead with the **two-level critical-path result**: MAC-related at PE/array; memory-address-dominated at full chip → SF vs FP16 exponent-alignment is not the tapeout Fmax lever.  
- Keep 1.2–1.7× SF-vs-FP16 as **literature estimate**, not measured.

**Section 5**

- Report the negative software-opt results as the contribution: naive skip/bypass **regress** performance; element-wise sparse branch is **SIMT-unsafe**.  
- Propose compacted loops or hardware skip as future work — do not claim an achieved speedup.

---

## File index

| File | Role |
| --- | --- |
| `docs/paper_sections_4_5_measurements.md` | This report |
| `docs/hierarchical_run_extract.json` | Parsed PE/array/core/TT metrics |
| `docs/sta_critical_path_max_ss.txt` | Flat-GPU critical path extract |
| `docs/sta_fma_touching_path_max_ss.txt` | Flat-GPU non-critical FMA-touching path |
| `test/logs/hw_aware_opts_results.json` | Section 5 cycle / correctness data |
| `test/test_hw_aware_opts.py` | Bench source |
