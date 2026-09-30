#!/usr/bin/env python3
"""Write the FP16 and BF16 harden configs from the SF16 ones.

  core_tile/config.json -> core_tile/config_fp16.json, config_bf16.json
  openframe/config.json -> openframe/config_fp16.json, config_bf16.json

Tile: adds the floating-point sources and sets the core_tile NUMBER_FORMAT
parameter through SYNTH_PARAMETERS. The FP datapaths are deeper than SF16's,
and at the SF16 tile's 55% target density placement spread each FP unit
across the tile: its align/add paths ran through ~25 repeaters and routing
added 1.3-2.7 ns. The FP tiles therefore place at 70% target density and
repair to a 1.5 ns setup margin. FP16 is denser (0.56 utilisation against
0.50 for BF16): at 70% its post-route repairs congested global routing, so
it places at 62%, and synthesises with ABC's AREA 0 script, whose logic was
6% faster than AREA 2 on the FP16 PE for 0.8% more area. Everything else
(floorplan, pins, diode antenna repair) stays that of the signed-off SF16
tile. Jumper-only antenna repair inserted no jumpers on the FP16 tile and
left 629 nets; diodes fit.

Chip: points the core_tile macro at core_tile/views_fp16/ or views_bf16/.
The chip RTL does not depend on the format, since the tiles are black
boxes there.

Rerun after editing either SF16 config: ./make_variants.py
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
FP_SOURCES = ["fp_arith.sv", "fp_systolic_pe.sv", "fp_fma.sv", "fp_activation.sv"]
VARIANTS = {"fp16": 1, "bf16": 2}
TILE_OVERRIDES = {"fp16": {"PL_TARGET_DENSITY_PCT": 62, "SYNTH_STRATEGY": "AREA 0"}}


def load(path):
    with open(os.path.join(HERE, path)) as f:
        return json.load(f)


def save(path, cfg):
    with open(os.path.join(HERE, path), "w") as f:
        json.dump(cfg, f, indent=4)
        f.write("\n")
    print("wrote", path)


def retarget_views(node, views):
    """Replace ../core_tile/views/ with ../core_tile/<views>/ in every string."""
    if isinstance(node, dict):
        return {k: retarget_views(v, views) for k, v in node.items()}
    if isinstance(node, list):
        return [retarget_views(v, views) for v in node]
    if isinstance(node, str):
        return node.replace("../core_tile/views/", f"../core_tile/{views}/")
    return node


def main():
    tile = load("core_tile/config.json")
    chip = load("openframe/config.json")
    for name, fmt in VARIANTS.items():
        t = dict(tile)
        t["VERILOG_FILES"] = tile["VERILOG_FILES"] + [f"dir::../../src/{s}" for s in FP_SOURCES]
        t["SYNTH_PARAMETERS"] = [f"NUMBER_FORMAT={fmt}"]
        t["PL_TARGET_DENSITY_PCT"] = 70
        t["PL_RESIZER_SETUP_SLACK_MARGIN"] = 1.5
        t["GRT_RESIZER_SETUP_SLACK_MARGIN"] = 1.5
        t.update(TILE_OVERRIDES.get(name, {}))
        save(f"core_tile/config_{name}.json", t)
        save(f"openframe/config_{name}.json", retarget_views(chip, f"views_{name}"))


if __name__ == "__main__":
    main()
