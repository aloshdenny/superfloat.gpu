#!/usr/bin/env python3
"""
Give OpenSTA the chip's top-level activity as pins.

OpenSTA's read_vcd annotates pins: a variable inside a cell instance's scope
(tb/dut/<instance>/<pin>). tb_chip_power.v dumps the chip's top level as nets
(the tiles' insides are dumped with their cells), so this rewrites the VCD
header: each scalar net in the dut scope becomes aliased variables, one per
standard-cell pin on that net, sharing the net's identifier code. The value
changes are copied unchanged.

  vcd_pins.py <chip netlist .nl.v> <in.vcd> <out.vcd>
"""
import re
import shutil
import sys

CELL = re.compile(r"(sky130_fd_sc_hd__\w+)\s+(\\\S+\s|\S+)\s*\((.*?)\);", re.S)
PIN = re.compile(r"\.(\w+)\(\s*(\\\S+\s|[^()\s]+)\s*\)")


def net_pins(netlist: str) -> dict:
    """net name (as Icarus writes it) -> [(instance, pin)]."""
    pins = {}
    for cell, inst, body in CELL.findall(open(netlist).read()):
        if re.match(r"sky130_fd_sc_hd__(fill|decap|tapvpwrvgnd)_", cell):
            continue
        inst = inst.strip().lstrip("\\")
        for pin, net in PIN.findall(body):
            pins.setdefault(net.strip(), []).append((inst, pin))
    return pins


def main(netlist: str, src: str, dst: str) -> None:
    pins = net_pins(netlist)
    out = open(dst, "w")
    scope = []
    mapped = kept = 0
    with open(src) as f:
        for line in f:
            t = line.split()
            if t[:1] == ["$scope"]:
                scope.append(t[2])
            elif t[:1] == ["$upscope"]:
                scope.pop()
            elif t[:1] == ["$var"] and scope == ["tb_chip_power", "dut"] and len(t) == 6:
                code, name = t[3], t[4]                      # scalar: $var wire 1 <code> <name> $end
                if name in pins:
                    for inst, pin in pins[name]:
                        out.write(f"$scope module {inst} $end\n$var wire 1 {code} {pin} $end\n$upscope $end\n")
                    mapped += 1
                    continue
                kept += 1
            out.write(line)
            if t[:1] == ["$enddefinitions"]:
                break
        out.flush()
        shutil.copyfileobj(f, out, 1 << 24)
    out.close()
    print(f"[vcd_pins] {mapped} top-level nets mapped to cell pins, {kept} other top-level variables kept")


if __name__ == "__main__":
    main(*sys.argv[1:4])
