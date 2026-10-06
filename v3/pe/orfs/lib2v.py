#!/usr/bin/env python3
"""Verilog functional models for standard cells, from a Liberty file.

  lib2v.py <lib> <out.v>
GT2N: every (width, Vt) variant shares the functions, so each cell is written
for w31/w13 x lvt/hvt/svt/ulvt/elvt. Any other library (NanGate45, ...): each
cell under its own name.
- Combinational outputs become assigns; a three_state output is high
  impedance while its condition holds.
- ff groups become flip-flops (clear, preset; both active: clear_preset_var1,
  1 if absent, as GT2N's dffasync); latch groups become latches.
- An integrated clock gate (statetable, latch_posedge*) latches its enable
  pins while the clock is low and ANDs the latch with the clock.
- Cells with no output (antenna, filler, tap) become modules with inputs only.
Liberty operators: ! and postfix ' are NOT, & * AND, | + OR, ^ XOR.
Zero-delay, for functional gate-level simulation only.
"""
import re
import sys

lib = open(sys.argv[1]).read()
lib = re.sub(r"/\*.*?\*/", "", lib, flags=re.S)
lib = re.sub(r"\\\n", " ", lib)
GT2N = [f"{w}_{vt}" for w in ("w31", "w13") for vt in ("lvt", "hvt", "svt", "ulvt", "elvt")]
GT2N_SFX = r'_w(31|13)_(lvt|hvt|svt|ulvt|elvt)$'


def groups(text, kind):
    """(name, body) of each top-level-in-text group `kind (name) { ... }`."""
    for m in re.finditer(rf'\b{kind}\s*\(([^)]*)\)\s*\{{', text):
        start = m.end(); depth = 1; i = start
        while depth:
            c = text[i]
            depth += (c == '{') - (c == '}')
            i += 1
        name = m.group(1).strip()
        yield (name if "," in name else name.strip('"')), text[start:i - 1], m.start(), i


def strip_group(body, kind):
    out, last = [], 0
    for _, _, s, e in groups(body, kind):
        if s < last:
            continue
        out.append(body[last:s]); last = e
    return "".join(out) + body[last:]


def attr(body, name):
    m = re.search(rf'\b{name}\s*:\s*"?([^";\n]*)"?\s*;', body)
    return m.group(1).strip() if m else None


def vexpr(f):
    """Liberty boolean function -> Verilog expression."""
    f = f.strip()
    if f in ("0", "1"):
        return "1'b" + f
    f = re.sub(r"(\w+|\([^()]*\))'", r"!\1", f)          # postfix NOT
    f = f.replace("!", "~").replace("*", "&").replace("+", "|")
    # Juxtaposition as AND: "A B" -> "A & B" (names or brackets next to each other).
    return re.sub(r"([\w)])\s+(?=[\w(~])", r"\1 & ", f)


def pins(body):
    out = []
    for name, pb, _, _ in groups(body, "pin"):
        out.append((name, attr(pb, "direction"), attr(pb, "function"), attr(pb, "three_state"),
                    attr(pb, "state_function"), pb))
    return out


def module(mn, body):
    body = strip_group(body, "test_cell")
    ps = pins(body)
    ins = [p[0] for p in ps if p[1] == "input"]
    outs = [p for p in ps if p[1] in ("output", "inout")]
    lines = [f"module {mn} ({', '.join(ins + [p[0] for p in outs])});"]
    lines += [f"  input {p};" for p in ins]
    lines += [f"  output {p[0]};" for p in outs]
    ff = next(groups(body, "ff"), None)
    latch = next(groups(body, "latch"), None)
    icg = attr(body, "clock_gating_integrated_cell")
    state = {}
    if ff:
        names = [x.strip().strip('"') for x in ff[0].split(",")]
        iq, iqn = names[0], (names[1] if len(names) > 1 else None)
        g = ff[1]
        clk, nxt = attr(g, "clocked_on"), attr(g, "next_state")
        clr, pre = attr(g, "clear"), attr(g, "preset")
        both = {"L": "1'b0", "H": "1'b1"}.get(attr(g, "clear_preset_var1") or "H", "1'b1")
        lines.append(f"  reg {iq};")
        def edge(e):
            e = e.strip().strip("()").strip()
            return f"negedge {e[1:].strip('() ')}" if e.startswith("!") else f"posedge {e}"
        sens = [edge(clk)] + ([edge(clr)] if clr else []) + ([edge(pre)] if pre else [])
        lines.append(f"  always @({' or '.join(sens)})")
        conds = []
        if clr and pre:
            conds.append(f"    if (({vexpr(clr)}) && ({vexpr(pre)})) {iq} <= {both};")
        if clr:
            conds.append(f"    {'else ' if conds else ''}if ({vexpr(clr)}) {iq} <= 1'b0;")
        if pre:
            conds.append(f"    {'else ' if conds else ''}if ({vexpr(pre)}) {iq} <= 1'b1;")
        conds.append(f"    {'else ' if conds else ''}{iq} <= {vexpr(nxt)};")
        lines += conds
        state = {iq: iq}
        if iqn:
            state[iqn] = f"(~{iq})"
    elif latch:
        names = [x.strip().strip('"') for x in latch[0].split(",")]
        iq, iqn = names[0], (names[1] if len(names) > 1 else None)
        g = latch[1]
        en, d = attr(g, "enable"), attr(g, "data_in")
        clr, pre = attr(g, "clear"), attr(g, "preset")
        lines.append(f"  reg {iq};")
        lines.append("  always @*")
        conds = []
        if clr:
            conds.append(f"    if ({vexpr(clr)}) {iq} = 1'b0;")
        if pre:
            conds.append(f"    {'else ' if conds else ''}if ({vexpr(pre)}) {iq} = 1'b1;")
        conds.append(f"    {'else ' if conds else ''}if ({vexpr(en)}) {iq} = {vexpr(d)};")
        lines += conds
        state = {iq: iq}
        if iqn:
            state[iqn] = f"(~{iq})"
    elif icg:
        ck = next(p[0] for p in ps if attr(p[5], "clock_gate_clock_pin") == "true")
        ens = [p[0] for p in ps if attr(p[5], "clock_gate_enable_pin") == "true" or attr(p[5], "clock_gate_test_pin") == "true"]
        if not icg.startswith("latch_posedge"):
            raise SystemExit(f"{mn}: clock gate style {icg} not modelled")
        st = next(groups(body, "statetable"), None)
        iq = st[0].split(",")[-1].strip().strip('"') if st else "IQ"
        lines.append(f"  reg {iq};")
        lines.append(f"  always @* if (!{ck}) {iq} = {' | '.join(ens)};")
        state = {iq: iq}
    for p, d, f, ts, sf, _ in outs:
        f = f or sf
        if f is None:
            lines.append(f"  assign {p} = 1'bx;")
            continue
        e = vexpr(f)
        for k in sorted(state, key=len, reverse=True):
            e = re.sub(rf"\b{k}\b", state[k], e)
        if ts:
            e = f"({vexpr(ts)}) ? 1'bz : ({e})"
        lines.append(f"  assign {p} = {e};")
    lines.append("endmodule")
    return "\n".join(lines)


cells = list(groups(lib, "cell"))
gt2n = any(re.search(GT2N_SFX, n) for n, *_ in cells)
mods, seen = [], set()
for name, body, _, _ in cells:
    if gt2n:
        base = re.sub(GT2N_SFX, '', name)
        if base in seen:
            continue
        seen.add(base)
        mods += [module(f"{base}_{v}", body) for v in GT2N]
    else:
        seen.add(name)
        mods.append(module(name, body))
open(sys.argv[2], "w").write("`timescale 1ns/1ps\n" + "\n\n".join(mods) + "\n")
print(f"wrote {len(mods)} modules ({len(seen)} cells{' x %d variants' % len(GT2N) if gt2n else ''})")
