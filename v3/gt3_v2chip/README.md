# The v2 SF16 chip on GT3 (3 nm)

ORFS designs for the v3 node study (`../nodes/gt3.md`), as `../gt2n_v2chip` at 2 nm: the v2 core tile (`v2_tile`, SF16) hardened on GT3 to GDS with `generate_abstract`, then the chip core (`v2_chip`: `superfloat_openframe` with four tile macros, no pad ring) with the tiles placed by `macro_place.tcl`. RTL: `../v2chip_rtl/` (the same sv2v as at 2 nm), installed as `designs/src/v2chip/`. Platform: `../platform_gt3/`.

Differences from 2 nm:
- **Clock 1000 ps, not 650 ps.** The tile misses 650 ps on GT3 (−201 ps at global route) and 900 ps (−50 ps); 1000 ps is the nearest round period it meets. The chip runs at the same period.
- **Power from the front.** GT3 has no backside layers, so each design has its own `pdn.tcl`: the platform's grid plus M11 stripes as the tile's block pins (above its M2–M10 routing), and on the chip M12 stripes over the whole core that connect to every tile's M11 pins.
- **Die from the tile LEF:** `chip_size.py` (gap 6 µm, logic strip 30 µm, as at 2 nm). The tile is 122.32 µm square, which gives the same 264 × 288 µm die as at 2 nm.

| | Tile | Chip |
|---|---|---|
| Die | 122.32 × 122.32 µm | 264 × 288 µm |
| Detailed-route violations | 0 | 0 |
| Setup at 1000 ps | +2.61 ps | −1,236 ps (register to output ports); register to register −790 ps (shared icache to the tiles' program-memory inputs) |
| Hold | −30.9 ps at 7 endpoints, all from input ports; register to register +11.4 ps | −22.8 ps at 5 endpoints (into the bus's address and data registers; the worst from a tile output) |
| Flip-flops | 11,495 | 2,796 outside the tiles |

Timing uses global-route estimated parasitics (`sta_final.tcl` as ORFS's final report does without OpenRCX rules). Run (on the pod): `CLK_PERIOD_PS=1000 make DESIGN_CONFIG=designs/gt3/v2_tile/config.mk FLOW_VARIANT=p1000 && make ... generate_abstract`, then `chip_size.py results/gt3/v2_tile/p1000/core_tile.lef` into `v2_chip/config.mk` and `CLK_PERIOD_PS=1000 make DESIGN_CONFIG=designs/gt3/v2_chip/config.mk FLOW_VARIANT=p1000`.

Renders: `../figs/gt3_tile.png`, `../figs/gt3_chip.png` (`../figs/render_gds.py`, device layers ACT and GATE and metals M0–M11, plus M12 on the chip).
