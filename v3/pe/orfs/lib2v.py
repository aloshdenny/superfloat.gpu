#!/usr/bin/env python3
"""Verilog functional models for the GT2N or GT3 cells, from a Liberty file.

  lib2v.py <lib> <out.v>
GT2N: every (width, Vt) variant shares the functions, so each cell is
written for w31/w13 x lvt/hvt/svt/ulvt/elvt. A library whose cell names
have no GT2N suffix (GT3: one RVT library) is written cell by cell, as named.
Combinational outputs become assigns; the dffasync flip-flop follows its ff
group (clear = !RESETN, preset = !SETN, both: Q = 1). Zero-delay, for
functional gate-level simulation only.
"""
import re, sys

lib = open(sys.argv[1]).read()
VARIANTS = [f"{w}_{vt}" for w in ("w31", "w13") for vt in ("lvt", "hvt", "svt", "ulvt", "elvt")]


def cells(text):
    for m in re.finditer(r'\bcell\s*\(\s*"?([A-Za-z0-9_]+)"?\s*\)\s*\{', text):
        start = m.end(); depth = 1; i = start
        while depth:
            c = text[i]
            depth += (c == '{') - (c == '}')
            i += 1
        yield m.group(1), text[start:i - 1]


def pins(body):
    out = []
    for m in re.finditer(r'\bpin\s*\(\s*"?([A-Za-z0-9_]+)"?\s*\)\s*\{', body):
        start = m.end(); depth = 1; i = start
        while depth:
            c = body[i]
            depth += (c == '{') - (c == '}')
            i += 1
        pb = body[start:i - 1]
        d = re.search(r'direction\s*:\s*"?(\w+)"?', pb)
        f = re.search(r'\bfunction\s*:\s*"([^"]*)"', pb)
        out.append((m.group(1), d.group(1) if d else None, f.group(1) if f else None))
    return out


mods = []
seen = set()
for name, body in cells(lib):
    base = re.sub(r'_w(31|13)_(lvt|hvt|svt|ulvt|elvt)$', '', name)
    if base in seen:
        continue
    seen.add(base)
    variants = VARIANTS if base != name else [None]
    ps = pins(body)
    ins = [p for p, d, f in ps if d == 'input']
    outs = [(p, f) for p, d, f in ps if d == 'output']
    ff = re.search(r'\bff\s*\(\s*(\w+)\s*,\s*(\w+)\s*\)\s*\{([^}]*)\}', body)
    for v in variants:
        mn = f"{base}_{v}" if v else name
        ports = ins + [p for p, _ in outs]
        lines = [f"module {mn} ({', '.join(ports)});"]
        lines += [f"  input {p};" for p in ins]
        if ff:
            iq, iqn, g = ff.group(1), ff.group(2), ff.group(3)
            clk = re.search(r'clocked_on\s*:\s*"([^"]*)"', g).group(1)
            nxt = re.search(r'next_state\s*:\s*"([^"]*)"', g).group(1)
            clr = re.search(r'clear\s*:\s*"\(?!(\w+)\)?"', g)
            pre = re.search(r'preset\s*:\s*"\(?!(\w+)\)?"', g)
            lines += [f"  output {p};" for p, _ in outs]
            lines.append(f"  reg {iq};")
            sens = [f"posedge {clk}"] + ([f"negedge {clr.group(1)}"] if clr else []) + ([f"negedge {pre.group(1)}"] if pre else [])
            lines.append(f"  always @({' or '.join(sens)})")
            conds = []
            if clr and pre:
                conds.append(f"    if (!{clr.group(1)} && !{pre.group(1)}) {iq} <= 1'b1;")
            if clr:
                conds.append(f"    {'else ' if conds else ''}if (!{clr.group(1)}) {iq} <= 1'b0;")
            if pre:
                conds.append(f"    {'else ' if conds else ''}if (!{pre.group(1)}) {iq} <= 1'b1;")
            conds.append(f"    {'else ' if conds else ''}{iq} <= {nxt.replace('!', '~')};")
            lines += conds
            for p, f in outs:
                lines.append(f"  assign {p} = {f.replace('!', '~').replace(iqn, '~' + iq)};")
        else:
            for p, f in outs:
                lines.append(f"  output {p};")
                lines.append(f"  assign {p} = {(f or '1' + chr(39) + 'bx').replace('!', '~')};")
        lines.append("endmodule")
        mods.append("\n".join(lines))
open(sys.argv[2], "w").write("`timescale 1ns/1ps\n" + "\n\n".join(mods) + "\n")
print(f"wrote {len(mods)} modules from {len(seen)} cells")
