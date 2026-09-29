#!/usr/bin/env python3
"""Derive the chip's DEF template from ChipFoundry's fixed wrapper DEF, with
every signal pin extended 3 um into the die.

The fixed pins reach 2 um outside the die and only 0.28-0.3 um inside, so
their centres lie outside the die. OpenROAD's detailed router then places
some of their access points outside every routing window and stops with
DRT-1231 ("Pin ... does not have access point"). Extending each pin inward
moves its centre inside the die.

Everything outside the wrapper boundary is unchanged, which is the only
region precheck compares against the empty template. Power pins are copied
as they are. The vendored file in openframe/.../fixed_dont_change/ is not
modified.

usage: ./extend_pins.py   (writes pins_extended.def next to this script)
"""
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "../../openframe/openlane/openframe_project_wrapper/"
                         "fixed_dont_change/openframe_project_wrapper.def")
OUT = os.path.join(HERE, "pins_extended.def")
EXTEND = 3000                    # DEF units (1000 per um)
POWER = {"vccd1", "vssd1", "vccd", "vssd", "vccd2", "vssd2", "vssa", "vdda",
         "vssa1", "vdda1", "vssa2", "vdda2", "vddio", "vssio"}

PIN = re.compile(r"^\s+- (\S+) \+ NET (\S+)")
PORT = re.compile(r"(\+ LAYER \S+ )\( (-?\d+) (-?\d+) \) \( (-?\d+) (-?\d+) \)(\s+\+ PLACED \( (-?\d+) (-?\d+) \) (\w+) ;)")


def main():
    text = open(SRC).read()
    die = re.search(r"DIEAREA \( (\d+) (\d+) \) \( (\d+) (\d+) \)", text)
    W, H = int(die.group(3)), int(die.group(4))
    out, name, changed = [], None, 0
    for line in text.splitlines(keepends=True):
        m = PIN.match(line)
        if m:
            name = m.group(1)
        p = PORT.search(line)
        if p and name and re.sub(r"\[.*", "", name) not in POWER:
            x0, y0, x1, y1 = (int(p.group(i)) for i in range(2, 6))
            px, py, orient = int(p.group(7)), int(p.group(8)), p.group(9)
            assert orient == "N", f"{name}: orientation {orient}"
            if px + x0 < 0:                  # west edge: grow towards +x
                x1 += EXTEND
            elif px + x1 > W:                # east edge: grow towards -x
                x0 -= EXTEND
            elif py + y0 < 0:                # south edge: grow towards +y
                y1 += EXTEND
            elif py + y1 > H:                # north edge: grow towards -y
                y0 -= EXTEND
            else:
                raise SystemExit(f"{name}: pin not on the die edge")
            line = line[:p.start()] + f"{p.group(1)}( {x0} {y0} ) ( {x1} {y1} ){p.group(6)}" + line[p.end():]
            changed += 1
        out.append(line)
    with open(OUT, "w") as f:
        f.write("".join(out))
    print(f"extended {changed} signal pins by {EXTEND / 1000:g} um -> {os.path.relpath(OUT, HERE)}")


if __name__ == "__main__":
    main()
