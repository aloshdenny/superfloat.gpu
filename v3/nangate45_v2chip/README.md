# The v2 SF16 chip on NanGate45 (45 nm)

ORFS designs for the 45 nm node (`../nodes/nangate45.md`): the v2 core tile (`v2_tile`, SF16) hardened to GDS with `generate_abstract`, then the chip core (`v2_chip`: `superfloat_openframe`, four tile macros placed by `macro_place.tcl`, no pad ring), both at 1.5 ns. RTL: `../v2chip_rtl/` (sv2v of the cf-openframe-v2 sources), copied to `designs/src/v2chip/`.

    make DESIGN_CONFIG=designs/nangate45/v2_tile/config.mk FLOW_VARIANT=p1500 CLK_PERIOD_PS=1500
    make DESIGN_CONFIG=designs/nangate45/v2_tile/config.mk FLOW_VARIANT=p1500 CLK_PERIOD_PS=1500 generate_abstract
    python3 chip_size.py results/nangate45/v2_tile/p1500/core_tile.lef 20 80   # DIE_AREA for v2_chip
    make DESIGN_CONFIG=designs/nangate45/v2_chip/config.mk CLK_PERIOD_PS=1500 TILE_VARIANT=p1500
    make DESIGN_CONFIG=... RUN_SCRIPT=sta_final.tcl run                         # signoff/*_sta.txt

| | Tile | Chip |
|---|---|---|
| Die | 694.16 × 694.16 µm | 1,450 × 1,510 µm |
| Detailed-route / antenna violations | 0 / 0 | 0 / 0 |
| Setup / hold slack at 1.5 ns (extracted) | +12.2 / +21.2 ps | +105.1 / +25.4 ps |

The chip's 20 µm channels and 80 µm logic strip replace the 2 nm rule's 6 and 30 µm, which failed global routing here (GRT-0116). Run on a 64-core Modal container, 2026-10-07 (`sf-tools/modal/jobs/n45_job.sh`).
