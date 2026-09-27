# SF16 vs IEEE FP16 / FP32 — Full LibreLane Baseline Comparison

Self-contained report. All numbers below are copied from each run’s `final/metrics.csv` and post-PnR `ws.max.rpt`. You should not need any other file to cite these results.

---

## 1. Experiment summary

| Item | Value |
| --- | --- |
| Goal | Harden SuperFloat (SF16) and IEEE FP16/FP32 FMA macros on Sky130 and compare area, timing, power, DRC/LVS |
| PDK | `sky130A` via `$HOME/.ciel` (ciel hash `74c0e6b118a67d94c24172143d3bd597473fa63d`) |
| Stdcell library | `sky130_fd_sc_hd` |
| Tool | LibreLane **v3.1.0.dev2** (Classic flow), entered via `nix-shell` in `/Users/aoxo/vscode/librelane` |
| Clock | **`CLOCK_PERIOD = 20.0` ns** → 50 MHz target (identical for every design in this report) |
| Default STA corner | `max_ss_100C_1v60` (worst setup corner used for pass/fail) |
| Hierarchy compared | FMA PE leaf + 2×2 systolic array (matches GPU→Core→Array→PE→FMA leaf of the architecture diagram) |
| Full 8-core × 4×4 GPU | Not hardened (PE/array are the iso-FMA baselines) |

### What was compared

| Baseline | Format | RTL top | Source |
| --- | --- | --- | --- |
| **SuperFloat (DUT)** | SF16 Q1.15 fixed-point MAC | `systolic_pe` / `systolic_array` | `src/systolic_pe.sv`, `src/systolic_array.sv` |
| **IEEE FP16** | binary16 FMA (HardFloat-class) | `fp16_systolic_pe` / `fp16_systolic_array` | `src/ieee_fma_pe.sv`, `src/fp_systolic_array.sv` |
| **IEEE FP32** | binary32 FMA (HardFloat-class) | `fp32_systolic_pe` | `src/ieee_fma_pe.sv` |

### Datapath difference (why area/timing diverge)

| Stage | SF16 PE | IEEE FP16 / FP32 PE |
| --- | --- | --- |
| S0 | Register A + stationary weight | Same pinout / control |
| S1 | 15×15 unsigned mantissa mul | Mantissa mul with hidden bit (11×11 FP16 / 24×24 FP32) + product exponent |
| S2 | Saturating signed add into accumulator | **Exponent-diff barrel align + add/sub** (registered) |
| S3 | (done) | **LZD + normalize + RNE pack** into IEEE accumulator |
| Subnormals | N/A (fixed-point) | Flush-to-zero |
| Rounding | Truncate Q1.15 upper bits | Round-to-nearest-even |

IEEE PE pinout matches SF PE: `clk, reset, enable, clear_acc, load_weight, compute_enable, a_in, b_in, a_out, b_out, acc_out`.

### Floorplan / synth knobs used

| Design | DIE_AREA (µm) | Target density | Hierarchy | Notes |
| --- | --- | --- | --- | --- |
| SF16 PE | `[0,0,160,200]` → die 32000 µm² | (legacy config) | flatten | Prior tapeout PE run |
| FP16 PE | `[0,0,320,360]` → die 115200 µm² | 55% | flatten | Extra space for align/LZD |
| FP32 PE | `[0,0,1400,1400]` → die 1.96e6 µm² | 28% | flatten | Large die for routability; post-GRT resizer off |
| SF16 2×2 array | `[0,0,400,280]` → die 112000 µm² | 65% | keep | Prior run |
| FP16 2×2 array | `[0,0,1600,1200]` → die 1.92e6 µm² | 30% | flatten | post-GRT resizer off |

Shared synth: `SYNTH_MUL_BOOTH=true`, `SYNTH_ADDER_TYPE=FA`, `SYNTH_STRATEGY=AREA 0`, `RT_MAX_LAYER=met4`.

### How to reproduce

```bash
cd /Users/aoxo/vscode/librelane
nix-shell --run 'cd /Users/aoxo/vscode/superfloat.gpu/librelane/fp16_systolic_pe && python3 -m librelane --pdk-root "$HOME/.ciel" ./config.json'
nix-shell --run 'cd /Users/aoxo/vscode/superfloat.gpu/librelane/fp32_systolic_pe && python3 -m librelane --pdk-root "$HOME/.ciel" ./config.json'
nix-shell --run 'cd /Users/aoxo/vscode/superfloat.gpu/librelane/fp16_systolic_array && python3 -m librelane --pdk-root "$HOME/.ciel" ./config.json'
```

### Run tags (source of every number below)

| Design | Run directory |
| --- | --- |
| SF16 PE | `librelane/systolic_pe/runs/RUN_2026-07-20_00-16-26` |
| IEEE FP16 PE | `librelane/fp16_systolic_pe/runs/RUN_2026-08-01_09-23-49` |
| IEEE FP32 PE | `librelane/fp32_systolic_pe/runs/RUN_2026-08-01_09-32-10` |
| SF16 2×2 array | `librelane/systolic_array/runs/RUN_2026-07-20_00-29-07` |
| IEEE FP16 2×2 array | `librelane/fp16_systolic_array/runs/RUN_2026-08-01_09-57-31` |

† **Implied Fmax** throughout = `1000 / (20 − worst_setup_slack_ns)` using `max_ss_100C_1v60` worst slack. This is **not** a binary-searched Fmax.

‡ **Power** is OpenROAD vectorless. Absolute Watts are less comparable across macros with very different utilization; area and STA are the primary metrics.

**Fair size metric:** use **`design__instance__area__stdcell`** (logic). Die area for FP macros was inflated for routability, so die/util alone overstates the IEEE penalty.

---

## 2. Executive comparison (PE)

| Metric | SF16 PE | IEEE FP16 PE | IEEE FP32 PE |
| --- | ---: | ---: | ---: |
| Stdcell area (µm²) | **18147.4** | **25396.9** | **96919.2** |
| Area vs SF16 | 1.000× | **1.400×** | **5.341×** |
| Setup WS `max_ss` (ns) | **+6.726457803363732** | **+0.17686830278758137** | **−5.045272786800869** |
| Implied Fmax (MHz) | **75.3378** | **50.4461** | **39.9277** |
| Meets 50 MHz @ `max_ss`? | **yes** (0 setup viols) | **yes** (0 setup viols) | **no** (69 setup viols @ `max_ss`) |
| Setup TNS (ns) | 0.0 | 0.0 | −75.92484722498082 |
| Magic DRC / KLayout DRC / LVS | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| Antenna violating nets | 0 | 0 | 0 |
| Route DRC errors | 0 | 0 | 0 |

**Headline:** At iso 20 ns, SF16 PE is **1.40× smaller** than IEEE FP16 and **5.34× smaller** than IEEE FP32, with **+6.73 ns** setup slack vs FP16’s **+0.18 ns**. FP32 **fails** the 50 MHz target by **5.05 ns**.

---

## 3. PE — area breakdown (exact)

| Metric | SF16 PE | IEEE FP16 PE | IEEE FP32 PE |
| --- | ---: | ---: | ---: |
| Die area (µm²) | 32000 | 115200 | 1960000 |
| Core area (µm²) | 26268.9 | 104105 | 1911350 |
| Instance area total (µm²) | 26268.9 | 104105 | 1911350 |
| **Stdcell area (µm²)** | **18147.4** | **25396.9** | **96919.2** |
| Utilization (stdcell) | 0.690831 | 0.243955 | 0.0507072 |
| Total instance count | 4815 | 26077 | 535881 |
| Stdcell instance count | 2231 | 3878 | 33868 |
| IO pin count | 88 | 88 | 168 |

### Area by cell class (µm²)

| Class | SF16 PE | IEEE FP16 PE | IEEE FP32 PE |
| --- | ---: | ---: | ---: |
| multi_input_combinational | 13031.2 | 18067.3 | 51116.5 |
| sequential | 1744.17 | 2999.13 | 5621.64 |
| timing_repair_buffer | 2389.79 | 1098.55 | 4229.06 |
| clock_buffer | 350.336 | 1143.6 | 989.699 |
| inverter | 131.376 | 255.245 | 658.131 |
| buffer | 15.0144 | 10.0096 | 10.0096 |
| tap_cell | 460.442 | 1812.99 | 34005.1 |
| fill_cell | 8121.54 | 78708 | 1814430 |
| antenna_cell | 25.024 | 10.0096 | 75.072 |

### Instance counts by class

| Class | SF16 PE | IEEE FP16 PE | IEEE FP32 PE |
| --- | ---: | ---: | ---: |
| multi_input_combinational | 1213 | 1893 | 5239 |
| sequential | 82 | 141 | 263 |
| timing_repair_buffer | 489 | 259 | 901 |
| clock_buffer | 31 | 62 | 67 |
| inverter | 35 | 68 | 174 |
| buffer | 3 | 2 | 2 |
| tap_cell | 368 | 1449 | 27178 |
| fill_cell | 2584 | 22199 | 502013 |
| antenna_cell | 10 | 4 | 30 |

**Note on fill/taps:** FP dies are much larger → fill and tap dominate total instance count. Logic comparison should use stdcell area / combo+seq counts, not total instance count.

### Area ratios (stdcell)

| Ratio | Computation | Value |
| --- | --- | ---: |
| FP16 / SF16 | 25396.9 / 18147.4 | **1.3995×** |
| FP32 / SF16 | 96919.2 / 18147.4 | **5.3407×** |
| FP32 / FP16 | 96919.2 / 25396.9 | **3.8162×** |
| Combo logic FP16 / SF16 | 18067.3 / 13031.2 | **1.3865×** |
| Combo logic FP32 / SF16 | 51116.5 / 13031.2 | **3.9226×** |
| Sequential FP16 / SF16 | 2999.13 / 1744.17 | **1.7195×** |
| Sequential FP32 / SF16 | 5621.64 / 1744.17 | **3.2225×** |

---

## 4. PE — timing (exact, all corners)

Sign convention: positive setup WS = meets period with margin.

### Setup worst slack (ns) — post-PnR

| Corner | SF16 PE | IEEE FP16 PE | IEEE FP32 PE |
| --- | ---: | ---: | ---: |
| **max_ss_100C_1v60** (signoff) | **+6.726457803363732** | **+0.17686830278758137** | **−5.045272786800869** |
| nom_ss_100C_1v60 | +6.882913100954026 | +0.41185900300415257 | −4.510980161535234 |
| min_ss_100C_1v60 | +7.024914182533327 | +0.5799361155449102 | −3.997936317383462 |
| max_tt_025C_1v80 | +13.193536414594593 | +9.707394274291042 | +6.648049410255064 |
| nom_tt_025C_1v80 | +13.28708025658143 | +9.824231484171717 | +6.935280102060585 |
| min_tt_025C_1v80 | +13.35818959923057 | +9.92672727670389 | +7.2051708860878945 |
| max_ff_n40C_1v95 | +15.710759360373853 | +13.641346216509705 | +11.332552106376244 |
| nom_ff_n40C_1v95 | +15.772258612250045 | +13.719234137049709 | +11.522880753495066 |
| min_ff_n40C_1v95 | +15.818431456882434 | +13.78675523878178 | +11.700129196657029 |

### Setup TNS / WNS / violation counts

| Metric | SF16 PE | IEEE FP16 PE | IEEE FP32 PE |
| --- | ---: | ---: | ---: |
| timing__setup__tns (ns) | 0.0 | 0.0 | −75.92484722498082 |
| timing__setup__wns | 0.0 | 0.0 | (negative; see WS) |
| setup_vio count (all corners aggregate metric) | 0 | 0 | 158 |
| setup_vio @ max_ss_100C_1v60 | 0 | 0 | **69** |
| setup reg-to-reg WS @ max_ss (ns) | +6.726458 | +0.176868 | −5.045273 |

### Hold worst slack (ns)

| Corner | SF16 PE | IEEE FP16 PE | IEEE FP32 PE |
| --- | ---: | ---: | ---: |
| max_ss_100C_1v60 | +0.5266024432234705 | +0.6760409090550792 | (see note) |
| min_ff_n40C_1v95 | +0.02907635325920966 | +0.0885210263479246 | — |
| Overall reported hold WS | −0.0019168556173789432 (1 viol @ max_ff only) | +0.0885210263479246 | −0.4560250084404708 |
| hold_vio @ max_ss | 0 | 0 | 81 |
| hold TNS (ns) | −0.0019168556173789432 | 0.0 | −12.33156101025413 |

FP32 hold is also failing at ss corners (81 viols @ `max_ss`); SF16 has a negligible hold WNS only on `max_ff` (−0.0019 ns, 1 path).

### Implied Fmax @ max_ss (from setup WS)

| Design | Formula | Implied Fmax |
| --- | --- | ---: |
| SF16 PE | 1000 / (20 − 6.726457803363732) | **75.3378 MHz** |
| FP16 PE | 1000 / (20 − 0.17686830278758137) | **50.4461 MHz** |
| FP32 PE | 1000 / (20 − (−5.045272786800869)) | **39.9277 MHz** |

| Fmax ratio | Value |
| --- | ---: |
| FP16 / SF16 | 50.4461 / 75.3378 = **0.6696×** |
| FP32 / SF16 | 39.9277 / 75.3378 = **0.5299×** |
| SF16 advantage vs FP16 | +24.89 MHz (∼49% higher implied Fmax) |
| SF16 advantage vs FP32 | +35.41 MHz (∼89% higher implied Fmax) |

---

## 5. PE — power (exact, vectorless)

| Metric | SF16 PE | IEEE FP16 PE | IEEE FP32 PE |
| --- | ---: | ---: | ---: |
| power__total (W) | 0.0027342247776687145 | 0.0017451621824875474 | 0.007883314043283463 |
| power__internal__total (W) | 0.0014314730651676655 | 0.001099564484320581 | 0.0036541360896080732 |
| power__switching__total (W) | 0.0013027236564084888 | 0.000645493040792644 | 0.004227317404001951 |
| power__leakage__total (W) | 2.7955913139976474e-8 | 1.0468689737308523e-7 | 1.8605260265758261e-6 |
| Total (mW) | **2.734** | **1.745** | **7.883** |

FP16 total power reading is **lower** than SF16 despite larger logic — treat cautiously: FP16 util is only 0.24 vs SF16 0.69, and vectorless activity does not model real MAC traffic. Prefer area + STA for the paper claim.

---

## 6. PE — routing, IR drop, signoff

| Metric | SF16 PE | IEEE FP16 PE | IEEE FP32 PE |
| --- | ---: | ---: | ---: |
| Detailed route wirelength | 45931 | 71592 | 337392 |
| Max wirelength | 328.6 | 563.16 | (present in metrics) |
| Route vias | 12504 | 17467 | 48608 |
| Route nets | 1877 | 2450 | 6704 |
| Global-route wirelength | 74913 | 110896 | 446009 |
| route__drc_errors (final) | 0 | 0 | 0 |
| Antenna violating nets / pins | 0 / 0 | 0 / 0 | 0 / 0 |
| Antenna diodes inserted | 2 | 1 | 20 |
| Magic DRC errors | 0 | 0 | 0 |
| KLayout DRC errors | 0 | 0 | 0 |
| Magic illegal overlap | 0 | 0 | 0 |
| LVS error count | 0 | 0 | 0 |
| LVS unmatched device/net/pin | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| Synthesis check errors | 0 | 0 | 0 |
| IR drop avg (V) | 0.000527 | 0.0000486 | 0.00000857 |
| IR drop worst (V) | 0.001580 | 0.000419 | 0.000453 |
| Worst VPWR (nom_tt) | 1.79842 | 1.79958 | 1.79955 |

All three PE macros are **manufacturability-clean** (DRC/LVS/antenna/route DRC = 0). Only FP32 fails **timing** at the shared 20 ns period.

---

## 7. Executive comparison (2×2 array)

| Metric | SF16 array | IEEE FP16 array |
| --- | ---: | ---: |
| Stdcell area (µm²) | **85931.2** | **139775** |
| Area vs SF16 | 1.000× | **1.627×** |
| Setup WS `max_ss` (ns) | **+7.62432627501624** | **−0.41937832171799466** |
| Implied Fmax (MHz) | **80.8037** | **48.9731** |
| Meets 50 MHz @ `max_ss`? | **yes** | **no** (3 setup viols @ `max_ss`) |
| Setup TNS (ns) | 0.0 | −0.6044356297668121 |
| Magic / KLayout DRC / LVS / antenna | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 0 |

IEEE FP32 2×2 array was **not** completed (FP32 PE already needed a 1400×1400 µm die; array routing was abandoned after PE signoff).

---

## 8. Array — area breakdown (exact)

| Metric | SF16 array | IEEE FP16 array |
| --- | ---: | ---: |
| Die area (µm²) | 112000 | 1920000 |
| Core area (µm²) | 99382.8 | 1871270 |
| **Stdcell area (µm²)** | **85931.2** | **139775** |
| Utilization | 0.864648 | 0.0746953 |
| Total instances | 15018 | 517452 |
| Stdcell instances | 10098 | 37708 |
| IO pins | 137 | 137 |

### Area by cell class (µm²)

| Class | SF16 array | IEEE FP16 array |
| --- | ---: | ---: |
| multi_input_combinational | 54667.4 | 70284.9 |
| sequential | 8423.08 | 12570.8 |
| timing_repair_buffer | 16678.5 | 16174.3 |
| clock_buffer | 3263.13 | 5924.43 |
| inverter | 569.296 | 1188.64 |
| buffer | 50.048 | 20.0192 |
| tap_cell | 1801.73 | 33472.1 |
| fill_cell | 13451.7 | 1731500 |
| antenna_cell | 467.949 | 97.5936 |

### Instance counts by class

| Class | SF16 array | IEEE FP16 array |
| --- | ---: | ---: |
| multi_input_combinational | 5040 | 7402 |
| sequential | 396 | 591 |
| timing_repair_buffer | 2737 | 2333 |
| clock_buffer | 137 | 267 |
| inverter | 149 | 313 |
| buffer | 10 | 4 |
| tap_cell | 1440 | 26752 |
| fill_cell | 4920 | 479744 |
| antenna_cell | 187 | 39 |

### Array area ratios

| Ratio | Value |
| --- | ---: |
| FP16 / SF16 stdcell | 139775 / 85931.2 = **1.6266×** |
| Combo FP16 / SF16 | 70284.9 / 54667.4 = **1.2857×** |
| Sequential FP16 / SF16 | 12570.8 / 8423.08 = **1.4924×** |

Rough consistency check: 4 × FP16 PE stdcell ≈ 4 × 25396.9 = 101587.6 µm²; measured array stdcell 139775 µm² → **∼1.38× PE×4**, attributable to array interconnect, input registers, and timing-repair buffers.

---

## 9. Array — timing (exact, all corners)

### Setup worst slack (ns)

| Corner | SF16 array | IEEE FP16 array |
| --- | ---: | ---: |
| **max_ss_100C_1v60** | **+7.62432627501624** | **−0.41937832171799466** |
| nom_ss_100C_1v60 | +7.771110197520894 | −0.15263701845601502 |
| min_ss_100C_1v60 | +7.908728118475011 | +0.11935341941484806 |
| max_tt_025C_1v80 | +13.369608021317172 | +9.753894856769568 |
| nom_tt_025C_1v80 | +13.461571793850675 | +9.844751958960828 |
| min_tt_025C_1v80 | +13.558814899060184 | +9.935670345464777 |
| max_ff_n40C_1v95 | +15.771860708306766 | +13.627482639164517 |
| nom_ff_n40C_1v95 | +15.832391845678107 | +13.681850706307255 |
| min_ff_n40C_1v95 | +15.889395138266623 | +13.735542869653486 |

| Metric | SF16 array | IEEE FP16 array |
| --- | ---: | ---: |
| Setup TNS (ns) | 0.0 | −0.6044356297668121 |
| setup_vio @ max_ss | 0 | **3** |
| setup reg-to-reg WS @ max_ss | +7.624326 | −0.419378 |
| Hold WS (overall) | +0.31374342900606506 | +0.3072121533009318 |
| hold_vio @ max_ss | 0 | 0 |

### Implied Fmax @ max_ss

| Design | Formula | Implied Fmax |
| --- | --- | ---: |
| SF16 array | 1000 / (20 − 7.62432627501624) | **80.8037 MHz** |
| FP16 array | 1000 / (20 − (−0.41937832171799466)) | **48.9731 MHz** |

FP16 array misses 50 MHz by **0.419 ns** (∼2.1% period).

---

## 10. Array — power, routing, signoff

| Metric | SF16 array | IEEE FP16 array |
| --- | ---: | ---: |
| power__total (W) | 0.006961531471461058 | 0.00653852429240942 |
| power__internal__total (W) | 0.004097717348486185 | 0.004375652875751257 |
| power__switching__total (W) | 0.0028636862989515066 | 0.0021610253024846315 |
| power__leakage__total (W) | 1.2797987380963605e-7 | 1.8459780903867795e-6 |
| Total (mW) | **6.962** | **6.539** |
| Route wirelength | 277134 | 456319 |
| Max wirelength | 962.59 | 1097.85 |
| Route vias | 59745 | 76912 |
| Route nets | 8521 | 10913 |
| Global-route wirelength | 416842 | 623346 |
| route__drc_errors | 0 | 0 |
| Antenna nets / pins | 0 / 0 | 0 / 0 |
| Antenna diodes | 41 | 20 |
| Magic / KLayout DRC | 0 / 0 | 0 / 0 |
| LVS errors | 0 | 0 |
| IR drop avg / worst (V) | 0.000231 / 0.000669 | 0.0000123 / 0.000408 |

---

## 11. Side-by-side ratios (paper-ready)

### PE (iso 20 ns, stdcell area + max_ss STA)

| Claim | Exact |
| --- | --- |
| IEEE FP16 area overhead vs SF16 | **+39.95%** (1.3995×) |
| IEEE FP32 area overhead vs SF16 | **+434.07%** (5.3407×) |
| SF16 setup slack advantage vs FP16 | **+6.5496 ns** |
| SF16 setup slack advantage vs FP32 | **+11.7717 ns** |
| SF16 implied-Fmax advantage vs FP16 | **+24.89 MHz** (75.34 vs 50.45) |
| SF16 implied-Fmax advantage vs FP32 | **+35.41 MHz** (75.34 vs 39.93) |
| FP16 closes 50 MHz? | **Yes** (WS +0.1769 ns, 0 viols) |
| FP32 closes 50 MHz? | **No** (WS −5.0453 ns, 69 viols @ max_ss) |

### 2×2 array (iso 20 ns)

| Claim | Exact |
| --- | --- |
| IEEE FP16 area overhead vs SF16 | **+62.66%** (1.6266×) |
| SF16 setup slack advantage | **+8.0437 ns** |
| SF16 implied-Fmax advantage | **+31.83 MHz** (80.80 vs 48.97) |
| FP16 array closes 50 MHz? | **No** (WS −0.4194 ns, 3 viols @ max_ss) |

---

## 12. Interpretation

1. **SF16 wins iso-frequency area and timing** because it skips exponent align, LZD, and IEEE normalize/round — the combinational cost that dominates HardFloat-class FMAs on Sky130 HD.
2. **FP16 PE is the strongest IEEE baseline:** +0.18 ns slack at 20 ns, DRC/LVS clean, only **1.40×** SF16 stdcell area.
3. **FP32 PE is clean for manufacture but not for 50 MHz:** −5.05 ns setup, 69 failing paths @ `max_ss`, **5.34×** SF16 stdcell area. Closing 20 ns would need deeper pipelining and/or a longer period.
4. **Die area is not the fair metric** for FP macros here (util 5–24% after enlargement for GRT). Always cite **stdcell area**.
5. **Array confirms the PE story:** FP16 2×2 is **1.63×** SF16 area and barely misses 50 MHz (−0.42 ns).
6. **Power figures are secondary** (vectorless, util-skewed). Do not lead with “FP16 uses less power than SF16” without activity-aware simulation.
7. **Hierarchy note:** These macros are the FMA/Array leaves of GPU → Core → Array → PE → FMA. Full 8×4×4 chip harden was out of scope; PE + 2×2 is the apples-to-apples accelerator-unit baseline.

---

## 13. Limitations (embedded)

| Limitation | Detail |
| --- | --- |
| Not Berkeley HardFloat verbatim | Custom synthesizable HardFloat-**class** FMA (same stages: mul → align → add → LZD → norm → RNE), FTZ subnormals |
| Not iso-pipeline-depth | SF16 is 3-stage MAC; IEEE PE adds registered align/add + normalize (extra latency, same throughput once filled) |
| Not iso-die | FP floorplans enlarged for routability; compare stdcell area |
| FP32 array missing | Routing risk after PE congestion; PE numbers remain the FP32 baseline |
| Power | Vectorless only |
| Implied Fmax | Slack-derived, not period binary search |
| Functional IEEE completeness | Inf/NaN/FTZ handled; not a full SoftFloat compliance suite in this harden |

---

## 14. Quick copy block (for slides / paper table)

```
Sky130 HD, CLOCK_PERIOD=20.0 ns, LibreLane 3.1.0.dev2

PE stdcell area (µm²):  SF16 18147.4 | FP16 25396.9 (1.40×) | FP32 96919.2 (5.34×)
PE setup WS max_ss (ns): SF16 +6.726 | FP16 +0.177 | FP32 −5.045
PE implied Fmax (MHz):   SF16 75.34  | FP16 50.45  | FP32 39.93
PE DRC/LVS/antenna:      all 0/0/0

2×2 array stdcell (µm²): SF16 85931.2 | FP16 139775 (1.63×)
2×2 setup WS max_ss (ns): SF16 +7.624 | FP16 −0.419
2×2 implied Fmax (MHz):   SF16 80.80  | FP16 48.97
```
