#!/usr/bin/env python3
"""Write the platform's lef/gt3_std_cell_rvt.lef from GT3's, with every
signal pin's DIRECTION taken from the Liberty.

  patch_cell_lef.py <GT3 cell LEF> <GT3 Liberty> <out.lef>

Upstream declares 69 input pins INOUT (the flip-flops' D and inputs of most
complex gates; the Liberty has them as inputs): 67 are fixed here, the other
two are the D pins of the LEF-only dffasync_x2/x4. OpenROAD trusts the LEF:
eliminate_dead_logic then sees nets that only reach those pins as unloaded
and deletes their drivers (on an S2 block, 121,719 of 123,514 cells).
Pins the Liberty does not list (cells without Liberty) are left as they are.
"""
import re
import sys

lef_in, lib_in, out = sys.argv[1:4]
lib = open(lib_in).read()
dirs = {}
for c in re.finditer(r"\bcell\s*\(\s*\"?(\w+)\"?\s*\)", lib):
    start = c.end()
    nxt = re.search(r"\bcell\s*\(", lib[start:])
    body = lib[start:start + nxt.start()] if nxt else lib[start:]
    for p in re.finditer(r"\bpin\s*\(\s*\"?(\w+)\"?\s*\)\s*\{\s*(?:[^{}]*?)direction\s*:\s*(\w+)", body):
        dirs[(c.group(1), p.group(1))] = p.group(2).upper()

lef = open(lef_in).read()
fixed = []


def macro(m):
    name = m.group(1)

    def pin(p):
        d = dirs.get((name, p.group(1)))
        if d and d != p.group(2):
            fixed.append(f"{name}/{p.group(1)} {p.group(2)}->{d}")
            return p.group(0).replace(f"DIRECTION {p.group(2)}", f"DIRECTION {d}")
        return p.group(0)
    return re.sub(r"PIN (\w+)\s+DIRECTION (\w+) ;", pin, m.group(0))


lef = re.sub(r"MACRO (\S+).*?END \1\b", macro, lef, flags=re.S)
open(out, "w").write(lef)
print(f"wrote {out}: {len(fixed)} pin directions set from the Liberty")
