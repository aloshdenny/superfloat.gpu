# The v2 SF16 chip on GT2N (2 nm)

ORFS designs for the shuttle plan's section 6.9: the v2 core tile (`v2_tile`, SF16) hardened on GT2N to GDS, then the chip core (`v2_chip`: `superfloat_openframe` with four tile macros, no pad ring) with the tiles placed by `macro_place.tcl`. RTL: sv2v of the cf-openframe-v2 sources at d84897d (`core_tile.v` with RAM32.v appended; the chip top with `CORE_TILE_MACRO`), in `designs/src/v2chip/`.

| | Tile | Chip |
|---|---|---|
| Die | 122.15 × 122.15 µm | 264 × 288 µm |
| Detailed-route violations | 0 | 0 |
| Setup at 650 ps | +0.35 ps | −587 ps (top-level paths through the bus) |
| Hold | +0.79 ps | +1.30 ps |

Renders: `../figs/render_gds.py` (KLayout, front-side layers only); figures: `../figs/make_figs.py`.
