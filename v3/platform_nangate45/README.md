# NanGate45 platform (45 nm)

The 45 nm runs use ORFS's own `nangate45` platform, unchanged: `/OpenROAD-flow-scripts/flow/platforms/nangate45` in the `openroad/orfs:latest` Docker image. Nothing here was ported or written; this file records what the platform is and how it was validated.

## What it is

- **Library:** the NanGate 45 nm Open Cell Library (FreePDK45), "PDKv1.3_v2010_12", as modified by ORFS (abstracts regenerated from the GDS, an AOI21_X1 contact fix). The library is research-only and deliberately non-manufacturable.
- **One Liberty corner:** `lib/NangateOpenCellLibrary_typical.lib`, operating conditions `typical` (process corner TypTyp), **1.10 V, 25 °C**. One Vt and one cell architecture: 135 cells, X1 to X32 drive strengths. No other corner or Vt flavour ships with the platform.
- **Units:** time 1 ns, capacitance 1 fF, leakage 1 nW. Every SDC on this platform is in ns (GT2N and GT3 are in ps).
- **Metal stack:** metal1–metal10; routing on metal2–metal10 (`MIN_ROUTING_LAYER metal2`, `MAX_ROUTING_LAYER metal10`), clock on metal4 and up.
- **Power grid** (`grid_strategy-M1-M4-M7.tcl`): metal1 followpins, metal4 stripes (56 µm pitch), metal7 stripes (30 µm pitch) exported as the block's pins.
- **Cells kept out of synthesis** (`DONT_USE_CELLS`): TAPCELL_X1, FILLCELL_X1, AOI211_X1, OAI211_X1. Yosys maps adders to FA_X1/HA_X1 (`cells_adders.v`).
- **Extraction:** OpenRCX rules ship (`rcx_patterns.rules`), so routed designs are signed off on extracted parasitics. The S2 blocks stop at global routing and use its estimated parasitics, as at 2 nm, so the two nodes are measured the same way.
- **SRAM:** the platform's `fakeram45_*` macros are abstract placeholders (bsg_fakeram LEF and Liberty with no layout), so no SRAM density is measured at this node.
- **Gate-level models:** the platform ships no Verilog cell models (only Yosys mapping files), so `../pe/orfs/lib2v.py` writes zero-delay models from the Liberty: all 135 cells, including the ff groups with clear/preset (DFFR, DFFS, DFFRS), the latches (DLH, DLL), the integrated clock gates (CLKGATE, CLKGATETST: statetable), tristates and the tie cells.

## Image

`openroad/orfs:latest`, pulled 2026-10-06 onto a RunPod CPU pod (EU-RO-1). The image carries no git metadata and `openroad -version` prints `unknown`; its flow files are dated 2026-10-03. Yosys 0.68+post, KLayout 0.30.12, Icarus Verilog 11.0 (installed on the pod for the gate-level runs).

## Validation: ORFS's nangate45 gcd

`make DESIGN_CONFIG=designs/nangate45/gcd/config.mk`, the full flow to `6_final.gds`, unmodified (its own 0.25 ns clock):

| | |
|---|---|
| Die | 35.76 × 35.76 µm |
| Detailed-route violations | 0 |
| Antenna violations | 0 (nets and pins) |
| Extraction | OpenRCX, 3,647 wires |
| Setup at 0.25 ns (extracted) | WNS −0.16 ns, TNS −7.19 ns |
| Run time | 43 s |

gcd's 0.25 ns target is ORFS's own and tighter than gcd reaches on this library; the check here is that the platform runs end to end and routes clean.

## Gaps

- Typical corner only, one Vt: no slow/fast corner or Vt mix as on GT2N (five Vt flavours, two widths).
- No real SRAM (fakeram only).
- 2010-era library on a non-manufacturable PDK: absolute numbers are indicative of a 45 nm planar process, not of a foundry's.
