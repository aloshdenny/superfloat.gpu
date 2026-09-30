#!/usr/bin/env python3
"""Post-route ECO for residual max-slew / max-cap / max-fanout violations.

Classic LibreLane repairs slew, capacitance and fanout before detailed
routing only. Real parasitics (coupling included), and the antenna diodes the
detailed router inserts, can still push a few nets over a limit. This script
reads a finished run's signoff checks in every corner and writes an ECO
config that inserts buffers for them, routes again and re-runs the full
signoff sequence:

  slew or cap on a standard-cell driver   a buffer after the driver
                                          (--clock-buffer for CTS's clkbuf_*
                                          and delaybuf_* instances)
  cap on a driver of macro input pins     a buffer in front of each macro pin,
                                          placed at the pin (a core_tile clk
                                          pin is 0.28 pF, and CTS drives two
                                          of them from one buffer)
  fanout on a net whose extra loads are   a --buffer halfway along the net,
  antenna diodes                          in front of the real sink nearest
                                          the diodes (they gather where a
                                          long branch meets its gate)

The detailed router places the diodes, and an ECO on the routed state keeps
them on their net, so a fanout fix restarts from the state before detailed
routing (as --reroute does); the router then re-inserts diodes on the two
shorter nets. Otherwise the ECO starts from the routed state saved before
fill insertion.

usage: ./eco_fix.py RUN [ECO_RUN] [--config config.json] [--buffer CELL]
                                   [--clock-buffer CELL] [--reroute]
--config is the harden config the run used, relative to this directory or
absolute (e.g. config_fp16.json, ../openframe/config.json). The ECO config
eco_<run>.json is written next to it; the command to run it is printed.

To fix what an ECO left, pass the original run and then the ECO run, e.g.
./eco_fix.py runs/chip_20 runs/chip_20_eco. The checks of the ECO run are
read; the new ECO starts again from the original run's state and inserts the
earlier ECO's buffers along with the new ones.

A violation on a macro output pin (a tile's port at chip level) is reported
and skipped, as is one on an instance the ECO step cannot look up: it
escapes brackets in names, so CTS instances such as clkbuf_1_0__f_gpio_in[38],
whose DEF names are unescaped, are not found. The IR-drop step is left out
when the config disables it.
"""
import argparse
import glob
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DRIVER_PINS = {"X", "Y", "Q", "Q_N", "Z", "HI", "LO"}
COMP = re.compile(r"^\s*- (\S+) (\S+) .*?\+ (?:PLACED|FIXED) \( (-?\d+) (-?\d+) \) (\w+)")
CONN = re.compile(r"\( (\S+) (\S+) \)")

# Classic flow from detailed routing through signoff (LibreLane 3).
ECO_FLOW = [
    "Odb.InsertECOBuffers",
    "OpenROAD.DetailedRouting",
    "Odb.RemoveRoutingObstructions",
    "OpenROAD.CheckAntennas",
    "Checker.TrDRC",
    "Odb.ReportDisconnectedPins",
    "Checker.DisconnectedPins",
    "Odb.ReportWireLength",
    "Checker.WireLength",
    "OpenROAD.FillInsertion",
    "Odb.CellFrequencyTables",
    "OpenROAD.RCX",
    "OpenROAD.STAPostPNR",
    "OpenROAD.IRDropReport",
    "Magic.StreamOut",
    "KLayout.StreamOut",
    "Magic.WriteLEF",
    "Odb.CheckDesignAntennaProperties",
    "KLayout.XOR",
    "Checker.XOR",
    "Magic.DRC",
    "KLayout.DRC",
    "Checker.MagicDRC",
    "Checker.KLayoutDRC",
    "Magic.SpiceExtraction",
    "Checker.IllegalOverlap",
    "Netgen.LVS",
    "Checker.LVS",
    "Checker.SetupViolations",
    "Checker.HoldViolations",
    "Checker.MaxSlewViolations",
    "Checker.MaxCapViolations",
    "Misc.ReportManufacturability",
]


def step_dirs(run):
    """The run's step directories in step order."""
    dirs = [d for d in glob.glob(os.path.join(run, "[0-9]*-*")) if os.path.isdir(d)]
    return sorted(dirs, key=lambda d: int(os.path.basename(d).split("-")[0]))


def violations(run):
    """{'slew', 'cap', 'fanout'} -> set of violating pins, over every corner."""
    sta = [d for d in step_dirs(run) if d.endswith("-openroad-stapostpnr")][-1]
    headers = {"max slew": "slew", "max capacitance": "cap", "max fanout": "fanout"}
    found = {kind: set() for kind in headers.values()}
    for rpt in glob.glob(os.path.join(sta, "*", "checks.rpt")):
        section = None
        for line in open(rpt):
            if line.strip() in headers:
                section = headers[line.strip()]
            elif line.startswith("===="):
                section = None
            elif section and "(VIOLATED)" in line:
                found[section].add(line.split()[0])
    return found


def read_def(path, wanted):
    """Placements {instance: (master, x, y, orient, DEF name)} in um, and
    {pin: connections of its net} for the wanted instance/pin names.
    Instance names are unescaped; ports appear as ('PIN', port)."""
    comps, nets = {}, {}
    units, section, conns = 1000, None, None
    for line in open(path):
        s = line.strip()
        if section is None:
            if s.startswith("UNITS DISTANCE MICRONS"):
                units = int(s.split()[3])
            elif s.startswith("COMPONENTS "):
                section = "comp"
            elif s.startswith("NETS "):
                section = "net"
            continue
        if s.startswith("END "):
            section, conns = None, None
        elif section == "comp":
            m = COMP.match(line)
            if m:
                comps[m[1].replace("\\", "")] = (m[2], int(m[3]) / units, int(m[4]) / units, m[5], m[1])
        else:
            if s.startswith("- "):
                conns = []
            if conns is None:
                continue                          # routing of the current net
            head, plus, _ = s.partition("+")
            conns.extend((i.replace("\\", ""), p) for i, p in CONN.findall(head))
            if plus or s.endswith(";"):
                for i, p in conns:
                    if f"{i}/{p}" in wanted:
                        nets[f"{i}/{p}"] = conns
                conns = None
    return comps, nets


def macro_pins(lef):
    """(width, height), {pin: centre of its first shape} of a macro LEF."""
    size, pins, pin = None, {}, None
    for line in open(lef):
        t = line.split()
        if not t:
            continue
        if t[0] == "SIZE" and size is None:
            size = (float(t[1]), float(t[3]))
        elif t[0] == "PIN":
            pin = t[1]
        elif t[0] == "END" and t[1:2] == [pin]:
            pin = None
        elif t[0] == "RECT" and pin and pin not in pins:
            x0, y0, x1, y1 = map(float, t[1:5])
            pins[pin] = ((x0 + x1) / 2, (y0 + y1) / 2)
    return size, pins


def pin_location(comp, size, point):
    """Die coordinates (um) of a macro pin given in macro coordinates."""
    _, x, y, orient, _ = comp
    (w, h), (px, py) = size, point
    fx = {"N": px, "FS": px, "S": w - px, "FN": w - px}
    fy = {"N": py, "FN": py, "S": h - py, "FS": h - py}
    if orient not in fx:
        sys.exit(f"macro orientation {orient} is not supported")
    return [round(x + fx[orient], 3), round(y + fy[orient], 3)]


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("run", help="the run the ECO starts from")
    ap.add_argument("eco_run", nargs="?", help="an ECO of RUN whose checks are read instead")
    ap.add_argument("--config", default="config.json")
    ap.add_argument("--buffer", default="sky130_fd_sc_hd__buf_4")
    ap.add_argument("--clock-buffer", default="sky130_fd_sc_hd__clkbuf_8")
    ap.add_argument("--reroute", action="store_true",
                    help="start from the state before detailed routing")
    args = ap.parse_args()
    base = args.run.rstrip("/")
    run = (args.eco_run or base).rstrip("/")
    config = args.config if os.path.isabs(args.config) else os.path.join(HERE, args.config)
    cfg = json.load(open(config))
    cfg_dir = os.path.dirname(os.path.abspath(config))
    for r in {base, run}:
        if not [d for d in step_dirs(r) if d.endswith("-checker-wirelength")]:
            sys.exit(f"{r}: no routed state before fill insertion")
    found = violations(run)
    drivers = sorted(found["slew"] | found["cap"])
    if not drivers and not found["fanout"]:
        sys.exit(f"{run}: no slew/cap/fanout violations; nothing to do")

    pre_fill = [d for d in step_dirs(run) if d.endswith("-checker-wirelength")]
    routed = json.load(open(os.path.join(pre_fill[-1], "state_out.json")))
    comps, nets = read_def(routed["def"], set(drivers) | found["fanout"])
    macros = {}
    for name, views in (cfg.get("MACROS") or {}).items():
        lef = views["lef"][0]
        macros[name] = macro_pins(os.path.join(cfg_dir, lef[5:]) if lef.startswith("dir::") else lef)

    def findable(inst):
        """The ECO step escapes brackets before looking an instance up."""
        return inst in comps and comps[inst][4] == re.sub(r"([\[\]])", r"\\\1", inst)

    inserts, skipped, reroute = [], [], args.reroute
    if run != base:
        # The earlier ECO's buffers. A placed one may be a fanout fix, which
        # only holds on a reroute that drops the old diodes.
        inserts = json.load(open(os.path.join(run, "resolved.json"))).get("INSERT_ECO_BUFFERS") or []
        reroute = reroute or any(b.get("placement") for b in inserts)
    for pin in drivers:
        inst, _, name = pin.rpartition("/")
        if inst not in comps or comps[inst][0] in macros or name not in DRIVER_PINS:
            skipped.append(f"{pin} (not a cell driver)")
            continue
        cell = args.clock_buffer if inst.startswith(("clkbuf", "delaybuf")) else args.buffer
        macro_loads = [(i, p) for i, p in nets.get(pin, [])
                       if i in comps and comps[i][0] in macros and findable(i)]
        if macro_loads:
            for i, p in macro_loads:
                size, pins = macros[comps[i][0]]
                inserts.append({"target": f"{i}/{p}", "buffer": cell,
                                "placement": pin_location(comps[i], size, pins[p])})
        elif findable(inst):
            inserts.append({"target": pin, "buffer": cell})
        else:
            skipped.append(f"{pin} (instance name not found by the ECO step)")

    for pin in sorted(found["fanout"]):
        inst, _, name = pin.rpartition("/")
        loads = [(i, p) for i, p in nets.get(pin, []) if (i, p) != (inst, name)]
        diodes = [i for i, _ in loads if i in comps and "__diode" in comps[i][0]]
        real = [(i, p) for i, p in loads if i not in diodes and findable(i)]
        if not diodes or not real or not findable(inst):
            skipped.append(f"{pin} (fanout {len(loads)}, {len(diodes)} diodes)")
            continue
        cx, cy = (sum(comps[d][k] for d in diodes) / len(diodes) for k in (1, 2))
        sink, sink_pin = min(real, key=lambda s: (comps[s[0]][1] - cx) ** 2 + (comps[s[0]][2] - cy) ** 2)
        mid = [round((comps[inst][k] + comps[sink][k]) / 2, 3) for k in (1, 2)]
        inserts.append({"target": f"{sink}/{sink_pin}", "buffer": args.buffer, "placement": mid})
        reroute = True

    if skipped:
        print(f"not buffered: {' '.join(skipped)}")
    if not inserts:
        sys.exit(f"{run}: no violation this script can fix")

    steps = step_dirs(base)
    start = [d for d in steps if d.endswith("-checker-wirelength")][-1]
    if reroute:
        drt = next(i for i, d in enumerate(steps) if d.endswith("-openroad-detailedrouting"))
        start = [d for d in steps[:drt] if os.path.exists(os.path.join(d, "state_out.json"))][-1]
    # The ECO flow is listed step by step, so apply the config's one-for-one
    # step substitutions (the chip's extraction step) to it.
    subs = {k: v for k, v in ((cfg.get("meta") or {}).get("substituting_steps") or {}).items()
            if not k.startswith(("+", "-"))}
    flow = [subs.get(s, s) for s in ECO_FLOW
            if not (s == "OpenROAD.IRDropReport" and cfg.get("RUN_IRDROP_REPORT") is False)]
    flow = [s for s in flow if s is not None]
    cfg["meta"] = {"version": 2, "flow": flow}
    cfg["INSERT_ECO_BUFFERS"] = inserts
    name = os.path.basename(run)
    out = os.path.join(cfg_dir, f"eco_{name}.json")
    json.dump(cfg, open(out, "w"), indent=4)

    for b in inserts:
        at = f" at {b['placement']}" if b.get("placement") else ""
        print(f"  {b['buffer']} -> {b['target']}{at}")
    print(f"wrote {out}, starting from {os.path.basename(base)}/{os.path.basename(start)}")
    runner = "./chip_flow.py" if os.path.exists(os.path.join(cfg_dir, "chip_flow.py")) else "python3 -m librelane"
    print("run from the librelane checkout's nix-shell:")
    print(f"  {runner} --pdk-root $HOME/.ciel {out} "
          f"--with-initial-state {os.path.abspath(os.path.join(start, 'state_out.json'))} "
          f"--run-tag {name}_eco")


if __name__ == "__main__":
    main()
