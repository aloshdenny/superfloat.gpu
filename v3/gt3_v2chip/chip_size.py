#!/usr/bin/env python3
"""DIE_AREA / CORE_AREA for v2_chip from the tile's abstract LEF, by the
2 nm rule (v3/gt2n_v2chip: 122.15 um tile -> 264 x 288 die): width
2 w + 3 gap, height 2 h + 2 gap + strip, each rounded up to an even um;
core 2 um inside the die.
  chip_size.py <core_tile.lef> [gap 6] [strip 30]"""
import math
import re
import sys

lef = open(sys.argv[1]).read()
gap = float(sys.argv[2]) if len(sys.argv) > 2 else 6.0
strip = float(sys.argv[3]) if len(sys.argv) > 3 else 30.0
w, h = map(float, re.search(r"MACRO core_tile.*?SIZE ([\d.]+) BY ([\d.]+)", lef, re.S).groups())
W = 2 * math.ceil((2 * w + 3 * gap) / 2)
H = 2 * math.ceil((2 * h + 2 * gap + strip) / 2)
print(f"tile {w} x {h}")
print(f"export DIE_AREA  = 0 0 {W} {H}")
print(f"export CORE_AREA = 2 2 {W - 2} {H - 2}")
