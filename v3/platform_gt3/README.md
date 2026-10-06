# ORFS platform for GT3 (3 nm GAAFET)

An OpenROAD-flow-scripts platform for the GT3 PDK, written for the v3 node study (`v3/nodes/gt3.md`). Modeled on ORFS's own `flow/platforms/gt2n` (same group; GT3 and GT2N share the 0.042 × 0.144 µm site and the M0–RDL front-side stack, width for width and pitch for pitch).

**Source:** [azadnaeemi/GT3](https://github.com/azadnaeemi/GT3) at `65050ce0125f2f25eb1e9a0940e22b7c3bc5eb5c` (2025-11-14), BSD-3-Clause (its `LICENSE` is copied into the installed platform).

**Install** (on a pod with the `openroad/orfs` image): `bash install.sh [GT3 clone] [ORFS flow dir]` clones GT3 at that commit if needed and builds `flow/platforms/gt3`. Test design: `designs/gcd` (copy to `flow/designs/gt3/gcd`).

## Files

From GT3: `gds/gt3_6t_std_cell_rvt.gds` unchanged; the cell LEF, tech LEF and Liberty through the patch scripts below.

Written here:

| File | What |
|---|---|
| `config.mk` | Platform variables, after gt2n's: one RVT library, site `gt3v1`, signals M2 up, clocks M3 up, `MAX_ROUTING_LAYER` per design |
| `patch_lib.py` | `lib/gt3_rvt_tt_0p7v25c.lib` with `default_operating_conditions : 0p7v25c` added, so OpenSTA has a supply voltage (below) |
| `patch_cell_lef.py` | `lef/gt3_std_cell_rvt.lef` with every signal pin's direction from the Liberty (upstream declares 69 input pins INOUT) |
| `patch_tech_lef.py` | `lef/gt3_tech.lef` from GT3's tech LEF: BPR as a routing layer, VBPR as the BPR-to-M0 cut, power-tap vias, the Via4Array fix (below) |
| `tapcell.tcl` | Power-tap columns (GT3 has no tap cell) |
| `pdn.tcl` | Front-side grid onto the buried power rails |
| `setRC.tcl`, `itf_to_rc.py` | Per-layer R and C from `GT3/nxtgrd/GT3.itf`, with gt2n's own script and model |
| `make_tie_cells.py`, `tie_gds.py` | Tie-high and tie-low cells (GT3 has none), from GT2N's |
| `fastroute.tcl`, `cells_clkgate.v` | As gt2n (layer adjustments; pass-through clock gate for Yosys) |
| `gt3.lyt` | KLayout tech for the GDS merge: gt2n's LEF/DEF layer map without its backside layers. `install.sh` copies gt2n's `gt2.lyp` as `gt3.lyp`: GT2N and GT3 use the same GDS layer numbers (`GT3/icv_runset/gt3_techfile.layermap`) |

## Power: front side, onto buried power rails

GT3's tech LEF has no backside layers (GT2N has BM1–BM4), so power is delivered from the front. The cells' only `vdd`/`vss` pins are buried power rails (BPR, 32 nm, under the cell boundaries), and GT3's LVS deck connects BPR upward only through VBPR → SDCON → VSD → M0. GT3 ships no cell that makes that connection (no tap, endcap or well-tie cell), so the platform models it:
- **BPR** becomes a horizontal routing layer (width 0.032, spacing 0.112 from DRC BPR.1/BPR.2, pitch 0.144), as in gt2n's tech LEF.
- **VBPR** becomes the one cut between BPR and M0 (VSD and VG, which carry no LEF geometry, become masterslice). A BPR-to-M0 via therefore stands for the VBPR–SDCON–VSD stack; `setRC.tcl` gives it the two ITF via resistances in series (68.9 Ω).
- **Power-tap columns** (`tapcell.tcl`): two filler sites at the same x in every row, every `GT3_TAP_PITCH` = 4.032 µm from `GT3_TAP_OFFSET` = 1.008 µm. GT3's cells keep M0 off the row-boundary track, but their M1 pins come within 14 nm of the boundary, so a via landing on a rail needs the cells above and below it gone; aligned columns give that (ORFS's `tapcell` places a checkerboard, which would not). 2.1% of every row.
- **Grid** (`pdn.tcl`): BPR followpins; a vdd/vss pair of M3 stripes (28 nm) centred on the two tap sites, each with a stacked via VBPR–V0–V1–V2 onto every rail of its net; an M6 (horizontal, 4.608 µm pitch) and M7 (vertical, 4.032 µm) mesh of 76 nm stripes over them; block pins on M7. The stacked vias are fixed vias (`*_PWR` in the tech LEF) whose pads meet each layer's minimum area.

## Bring-up

ORFS's gcd (`designs/gcd`, 170 ps as on gt2n, `MAX_ROUTING_LAYER` M7) through `make` to the end: 8.95 µm die, 0 detailed-route violations, GDS merged with every cell matched, `check_power_grid`: every shape on vdd and vss connected (54 and 56 power-tap via stacks). It misses 170 ps by 253 ps (minimum period 423 ps): GT3 has RVT only, where gt2n's gcd picks from five Vts down to ELVT.

## Known gaps

- **Modeled power taps.** The BPR-to-M0 via and the tap columns are this platform's, not GT3's: GT3 has no tap cell. The VBPR cut is 12 × 12 nm (the tech LEF's VBPR width); GT3's ICV rules say 11 × 15 nm and inside SDCON, which a via straight to M0 is not.
- **Borrowed tie cells.** GT3 has no tie cells, and its only flip-flop (`dffasync_x1`) has active-low set and reset, so every flop ties two pins high. The tie cells are GT2N's `tiehigh`/`tielow` (w31 LVT) renamed: LEF and GDS geometry (same site, BPR rails and M0/M1 rules), and area, leakage and function from GT2N's Liberty (no timing arcs; a tie drives a constant). They are the platform's only non-GT3 cells.
- **One corner, one Vt:** typical 0.7 V / 25 °C, RVT, one nanosheet width. No W/Vt menu (gt2n loads ten flavours).
- **No latch, clock-gate, adder, mux, decap or tie cell**; `dffasync_x2`/`x4` are in the LEF but have no Liberty or GDS (`DONT_USE_CELLS`).
- **No extraction rules for OpenRCX** (ICT, NXTGRD and QRC only), so timing and power use estimated parasitics from `setRC.tcl`, as on gt2n.
- **DRC and LVS decks are ICV-only**: results are routed with zero detailed-route violations, not signed off.
- **No SRAM macros** in the PDK.
- **Liberty power data.** GT3's Liberty has no `pg_pin` groups and no default operating conditions, so OpenSTA finds no supply voltage and reports zero switching power; `patch_lib.py` names the library's only operating conditions (0.7 V) the default. Many of its internal-power tables are negative at ordinary loads (an inverter's output rise is −0.37 fJ from 1 to 29 fF), so a block's clock-network internal power comes out negative (−3.1 mW on an S2 block, against +8.6 mW switching): OpenSTA's totals are reported as they come.
- Upstream fixes: GT3's cell LEF declares 69 input pins `INOUT` (every flip-flop D, and inputs of most complex gates), which makes OpenROAD's `eliminate_dead_logic` delete everything that only feeds them (121,719 of an S2 block's 123,514 cells); `patch_cell_lef.py` sets them from the Liberty. GT3's `Via4Array` cut rectangle reads y from −0.105 (GT2N's: −0.0105); corrected here. GT3's README puts the ICT under `ict/`; it is `qrc/GT3.ict`.
