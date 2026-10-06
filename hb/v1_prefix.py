#!/usr/bin/env python3
"""
The v1 RTL with every module renamed sf1_<name>, as one file.

bsg_manycore has modules of its own called alu, lsu, ... so the v1 sources
cannot be compiled beside it as they are. This rewrites module declarations
and instantiations only; nothing else in the RTL changes.

  python3 v1_prefix.py <src dir> <out.sv> <file> ...
"""
import re
import sys

src, out, files = sys.argv[1], sys.argv[2], sys.argv[3:]
texts = [open(f"{src}/{f}").read() for f in files]
names = set()
for t in texts:
    names |= set(re.findall(r"^\s*module\s+([A-Za-z_]\w*)", t, re.M))
alt = "|".join(sorted(names, key=len, reverse=True))
decl = re.compile(rf"^(\s*module\s+)({alt})\b", re.M)
inst = re.compile(rf"^(\s*)({alt})(\s*(?:#|[A-Za-z_]\w*\s*\())", re.M)
with open(out, "w") as f:
    for name, t in zip(files, texts):
        t = decl.sub(lambda m: m.group(1) + "sf1_" + m.group(2), t)
        t = inst.sub(lambda m: m.group(1) + "sf1_" + m.group(2) + m.group(3), t)
        f.write(f"// ---- {name}\n{t}\n")
print(f"{out}: {len(names)} modules prefixed: {' '.join(sorted(names))}")
