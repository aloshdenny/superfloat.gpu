sv2v of the v2 SF16 chip at cf-openframe-v2 d84897d, the RTL of the 2 nm chip (v3/gt2n_v2chip):
- `core_tile.v`: src/core_tile.sv (NUMBER_FORMAT 0) and its modules, with src/RAM32.v appended.
- `chip_top.v`: superfloat_openframe and the chip's own modules, `-DCORE_TILE_MACRO` (core_tile a black box).
