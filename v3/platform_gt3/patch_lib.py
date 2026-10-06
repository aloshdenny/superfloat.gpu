#!/usr/bin/env python3
"""Write the platform's lib/gt3_rvt_tt_0p7v25c.lib from GT3's with one line
added: default_operating_conditions : 0p7v25c.

  patch_lib.py <GT3 Liberty> <out.lib>

GT3's Liberty has no pg_pin groups and no default operating conditions, so
OpenSTA finds no supply voltage for any cell and reports zero switching
power (it takes the voltage from the pg_pin's voltage_map, else from the
operating conditions, else 0). The library's only operating conditions are
0p7v25c (0.7 V, 25 C); naming them the default gives switching power at
0.7 V. Delays are table lookups with no derating, so timing is unchanged.
"""
import re
import sys

src, out = sys.argv[1], sys.argv[2]
t = open(src).read()
if "default_operating_conditions" not in t:
    m = re.search(r"operating_conditions\s*\(\s*0p7v25c\s*\)\s*\{[^}]*\}\n", t)
    if not m:
        sys.exit("patch_lib: operating_conditions(0p7v25c) not found")
    t = t[:m.end()] + "  default_operating_conditions : 0p7v25c ; \n" + t[m.end():]
open(out, "w").write(t)
print(f"wrote {out}")
