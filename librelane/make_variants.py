#!/usr/bin/env python3
"""Write the FP16 and BF16 harden configs from the SF16 ones.

  core_tile/config.json -> core_tile/config_fp16.json, config_bf16.json
  openframe/config.json -> openframe/config_fp16.json, config_bf16.json

Tile: adds the floating-point sources and sets the core_tile NUMBER_FORMAT
parameter through SYNTH_PARAMETERS. Antenna repair uses jumpers only: the
FP16 tile reaches ~0.57 utilisation and diodes could not be legalised
(DPL-0036). Everything else (floorplan, pins, closure settings) stays that
of the signed-off SF16 tile.

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
        t["GRT_ANTENNA_REPAIR_JUMPER_ONLY"] = True
        t["DRT_ANTENNA_REPAIR_JUMPER_ONLY"] = True
        save(f"core_tile/config_{name}.json", t)
        save(f"openframe/config_{name}.json", retarget_views(chip, f"views_{name}"))


if __name__ == "__main__":
    main()
