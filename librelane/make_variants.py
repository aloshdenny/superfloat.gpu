#!/usr/bin/env python3
"""Write the SF16, FP16 and BF16 harden configs from the base ones.

  core_tile/config.json -> core_tile/config_{sf16,fp16,bf16}.json
  openframe/config.json -> openframe/config_{sf16,fp16,bf16}.json

Every format gets the same flow settings (COMMON): the union of what any v1
tile needed to close. In v1 the FP tiles had their own: ABC's AREA 0 script
(6% faster logic than AREA 2 on the FP16 PE for 0.8% more area), a 1.5 ns
placement repair margin, and for FP16 a 3 ns post-global-route margin,
because routing cost the FP tiles 1.1-2.6 ns of setup. SF16 ran at 0.3 ns.
Giving them to one format only biases its peak clock, so all three take them.

Each tile is sized by one rule: the same cell utilization for all three
formats. FP16, the largest tile, sets it, in the largest macro the
floorplan has room for (1500 x 2250 um). The others are as wide and only as
tall as that utilization needs. Tiles 0 and 1 end at the centre strip
(y = STRIP_BOTTOM) and tiles 2 and 3 start at its top, so a shorter tile
moves tiles 0 and 1 up and keeps every tile's pin edge on the strip. Global
placement targets the same density for every tile (DENSITY_PCT).

The tile heights come from synthesis (SYNTH_AREA_UM2, from each format's
Yosys run) times the synthesis-to-signoff growth v1 measured (GROWTH).

The chip RTL does not depend on the format; each chip config points the
core_tile macro at core_tile/views_<fmt>/.

Rerun after editing either base config: ./make_variants.py
"""
import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
FP_SOURCES = ["fp_arith.sv", "fp_systolic_pe.sv", "fp_fma.sv", "fp_activation.sv"]
FORMATS = {"sf16": 0, "fp16": 1, "bf16": 2}

TILE_WIDTH = 1500.0
MAX_TILE_HEIGHT = 2250.0
STRIP_BOTTOM = 2320.0             # top edge of tiles 0 and 1
HEIGHT_STEP = 10.0                # tile heights round up to 10 um

# Yosys cell area per format (um2, v2 RTL with COMMON, server toolchain), and
# v1's signoff / synthesis cell-area ratio (repair buffers, diodes, taps and
# decaps): SF16 1,401,520 / 926,001; FP16 1,861,440 / 1,238,878;
# BF16 1,633,720 / 1,057,015. None: not measured, keep the largest macro.
SYNTH_AREA_UM2 = {"sf16": 996111.6, "fp16": 1305134.2, "bf16": 1123080.9}
GROWTH = {"sf16": 1.5135, "fp16": 1.5025, "bf16": 1.5456}
# Global placement target, the same for every tile: FP16 routed at 55% in v1
# and congested at 62%.
DENSITY_PCT = 55

COMMON = {
    "SYNTH_STRATEGY": "AREA 0",
    "PL_RESIZER_SETUP_SLACK_MARGIN": 1.5,
    "GRT_RESIZER_SETUP_SLACK_MARGIN": 3.0,
}


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


def signoff_area(fmt):
    a = SYNTH_AREA_UM2[fmt]
    return None if a is None else a * GROWTH[fmt]


def utilization():
    """FP16's utilization in the largest macro: the target for every tile."""
    a = signoff_area("fp16")
    return None if a is None else a / (TILE_WIDTH * MAX_TILE_HEIGHT)


def tile_height(fmt):
    u = utilization()
    a = signoff_area(fmt)
    if u is None or a is None:
        return MAX_TILE_HEIGHT
    h = math.ceil(a / u / TILE_WIDTH / HEIGHT_STEP) * HEIGHT_STEP
    return min(round(h, 2), MAX_TILE_HEIGHT)


def main():
    tile = load("core_tile/config.json")
    chip = load("openframe/config.json")
    density = DENSITY_PCT
    u = utilization()
    if u is not None:
        print(f"target utilization (FP16 in the largest macro): {u:.3f}")
    for name, fmt in FORMATS.items():
        h = tile_height(name)
        t = dict(tile)
        if fmt:
            t["VERILOG_FILES"] = tile["VERILOG_FILES"] + [f"dir::../../src/{s}" for s in FP_SOURCES]
        t["SYNTH_PARAMETERS"] = [f"NUMBER_FORMAT={fmt}"]
        t.update(COMMON)
        t["PL_TARGET_DENSITY_PCT"] = density
        t["DIE_AREA"] = [0.0, 0.0, TILE_WIDTH, h]
        save(f"core_tile/config_{name}.json", t)

        c = retarget_views(chip, f"views_{name}")
        inst = c["MACROS"]["core_tile"]["instances"]
        for i in (0, 1):
            key = f"chip.gpu_inst.tiles[{i}].tile"
            inst[key]["location"] = [inst[key]["location"][0], round(STRIP_BOTTOM - h, 2)]
        save(f"openframe/config_{name}.json", c)
        print(f"  {name}: tile 1500 x {h} um, density {density}%")


if __name__ == "__main__":
    main()
