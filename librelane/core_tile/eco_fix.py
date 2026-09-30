#!/usr/bin/env python3
"""Post-route ECO for residual max-slew / max-cap / max-fanout violations.

Classic LibreLane repairs slew, capacitance and fanout before detailed
routing only. Real parasitics (coupling included), and the antenna diodes the
detailed router inserts, can still push a few nets over a limit. This script
reads a finished run's signoff checks in every corner and writes an ECO
config that inserts buffers for them, routes again and re-runs the full
signoff sequence:

  slew or cap on a standard-cell driver   a buffer after the driver, placed
                                          beside it (--clock-buffer for CTS's
                                          clkbuf_* and delaybuf_* instances,
                                          --near-buffer after a weak driver)
  cap on a driver of macro input pins     a buffer in front of each macro pin,
                                          placed at the pin (a core_tile clk
                                          pin is 0.28 pF, and CTS drives two
                                          of them from one buffer)
  fanout on a net whose extra loads are   a --buffer halfway along the net,
  antenna diodes                          in front of the real sink nearest
                                          the diodes (they gather where a
                                          long branch meets its gate)
  slew on the loads of a long net whose   a --long-buffer (--clock-buffer on a
  driver is within limits                 clock net) halfway along the
                                          routed path to the farthest such
                                          load, moved off any macro and its
                                          halo (a net routed around the tiles
                                          ran 3.6 mm on met1/met2)

The detailed router places the diodes, and an ECO on the routed state keeps
them on their net, so a fanout fix restarts from the state before detailed
routing (as --reroute does); the router then re-inserts diodes on the two
shorter nets. Otherwise the ECO starts from the routed state saved before
fill insertion.

usage: ./eco_fix.py RUN [ECO_RUN] [--config config.json] [--buffer CELL]
                                   [--clock-buffer CELL] [--long-buffer CELL]
                                   [--near-buffer CELL] [--reroute]
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
import heapq
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DRIVER_PINS = {"X", "Y", "Q", "Q_N", "Z", "HI", "LO"}
WEAK_DRIVER_PF = 0.06                 # max capacitance of a _1 gate, roughly
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
    """{'slew', 'cap', 'fanout'} -> set of violating pins, over every corner,
    and {'cap_limit'} -> {pin: its max capacitance (pF)}."""
    sta = [d for d in step_dirs(run) if d.endswith("-openroad-stapostpnr")][-1]
    headers = {"max slew": "slew", "max capacitance": "cap", "max fanout": "fanout"}
    found = {kind: set() for kind in headers.values()}
    found["cap_limit"] = {}
    for rpt in glob.glob(os.path.join(sta, "*", "checks.rpt")):
        section = None
        for line in open(rpt):
            if line.strip() in headers:
                section = headers[line.strip()]
            elif line.startswith("===="):
                section = None
            elif section and "(VIOLATED)" in line:
                found[section].add(line.split()[0])
                if section == "cap":
                    found["cap_limit"][line.split()[0]] = float(line.split()[1])
    return found


def route_segments(text, units):
    """[(x0, y0, x1, y1)] in um of a net's ROUTED/NEW wiring text."""
    segs, last, layer_next = [], None, False
    tokens = re.findall(r"\(|\)|[^\s()]+", text)
    i = 0
    while i < len(tokens):
        t = tokens[i]
        if t in ("ROUTED", "NEW", "FIXED", "COVER"):
            last, layer_next = None, True
        elif layer_next:
            layer_next = False                    # the layer name
        elif t == "(":
            x, y = tokens[i + 1], tokens[i + 2]
            px = last[0] if x == "*" and last else float(x) / units
            py = last[1] if y == "*" and last else float(y) / units
            if last:
                segs.append((last[0], last[1], px, py))
            last = (px, py)
            i = tokens.index(")", i)
        i += 1
    return segs


def read_def(path, wanted):
    """Placements {instance: (master, x, y, orient, DEF name)} in um,
    {pin: connections of its net}, {pin: routed segments of its net} and the
    pins on clock nets, for the wanted instance/pin names. Instance names are unescaped; ports appear
    as ('PIN', port)."""
    comps, nets, routes, clock_pins = {}, {}, {}, set()
    units, section, conns = 1000, None, None
    routing, route_pins = None, []
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
                if routing is not None:           # routing of a wanted net
                    routing.append(s)
                    if s.endswith(";"):
                        segs = route_segments(" ".join(routing), units)
                        for pin in route_pins:
                            routes[pin] = segs
                        routing = None
                continue
            head, plus, rest = s.partition("+")
            conns.extend((i.replace("\\", ""), p) for i, p in CONN.findall(head))
            if plus or s.endswith(";"):
                route_pins = [f"{i}/{p}" for i, p in conns if f"{i}/{p}" in wanted]
                for pin in route_pins:
                    nets[pin] = conns
                    if "USE CLOCK" in rest:
                        clock_pins.add(pin)
                if route_pins and not s.endswith(";"):
                    routing = ["+" + rest]
                conns = None
    return comps, nets, routes, clock_pins


def path_midpoint(segs, start, end):
    """(point, length): the point halfway along the routed path from start
    to end (um), and the path's length; None if the route does not join them."""
    key = lambda x, y: (round(x, 3), round(y, 3))
    # split each segment where another one ends on it (T-junctions, vias)
    ends = {key(x, y) for x0, y0, x1, y1 in segs for x, y in ((x0, y0), (x1, y1))}
    split = []
    for x0, y0, x1, y1 in segs:
        on = sorted((p for p in ends
                     if min(x0, x1) <= p[0] <= max(x0, x1) and min(y0, y1) <= p[1] <= max(y0, y1)
                     and (p[0] == round(x0, 3) == round(x1, 3) or p[1] == round(y0, 3) == round(y1, 3))),
                    key=lambda p: abs(p[0] - x0) + abs(p[1] - y0))
        pts = [key(x0, y0)] + on + [key(x1, y1)]
        split += [(a[0], a[1], b[0], b[1]) for a, b in zip(pts, pts[1:])]
    adj = {}
    for x0, y0, x1, y1 in split:
        a, b = key(x0, y0), key(x1, y1)
        if a != b:
            d = abs(x1 - x0) + abs(y1 - y0)
            adj.setdefault(a, []).append((b, d))
            adj.setdefault(b, []).append((a, d))
    if not adj:
        return None
    near = lambda p, nodes: min(nodes, key=lambda n: abs(n[0] - p[0]) + abs(n[1] - p[1]))
    src = near(start, adj)
    dist, prev, todo = {src: 0.0}, {}, [(0.0, src)]
    while todo:                                   # Dijkstra over the route
        d, n = heapq.heappop(todo)
        if d > dist[n]:
            continue
        for m, w in adj[n]:
            if d + w < dist.get(m, float("inf")):
                dist[m], prev[m] = d + w, n
                heapq.heappush(todo, (d + w, m))
    # a pin's own shape joins the last stretch of routing to it, so end at
    # the reachable node nearest the load
    dst = near(end, dist)
    path = [dst]
    while path[-1] != src:
        path.append(prev[path[-1]])
    path.reverse()
    half, walked = dist[dst] / 2, 0.0
    for (ax, ay), (bx, by) in zip(path, path[1:]):
        d = abs(bx - ax) + abs(by - ay)
        if walked + d >= half:
            f = (half - walked) / d
            return (ax + (bx - ax) * f, ay + (by - ay) * f), dist[dst]
        walked += d
    return path[-1], dist[dst]


def free_point(pt, keepout, core):
    """pt, or the nearest point just outside the keepout box that holds it,
    inside the core; None if there is none."""
    inside = lambda x, y, b: b[0] <= x <= b[2] and b[1] <= y <= b[3]
    x, y = pt
    boxes = [b for b in keepout if inside(x, y, b)]
    if not boxes:
        return [round(x, 3), round(y, 3)]
    b = boxes[0]
    candidates = [(b[0] - 3, y), (b[2] + 3, y), (x, b[1] - 3), (x, b[3] + 3)]
    ok = [c for c in candidates
          if not any(inside(*c, k) for k in keepout)
          and core[0] <= c[0] <= core[2] and core[1] <= c[1] <= core[3]]
    if not ok:
        return None
    cx, cy = min(ok, key=lambda c: abs(c[0] - x) + abs(c[1] - y))
    return [round(cx, 3), round(cy, 3)]


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
    ap.add_argument("--long-buffer", default="sky130_fd_sc_hd__buf_8")
    # buf_1 takes 3 sites; in the FP16 tile's crowded corner no run of 4 free
    # sites lay within 100 um of the weak drivers, only runs of 3
    ap.add_argument("--near-buffer", default="sky130_fd_sc_hd__buf_1",
                    help="buffer after a driver whose max capacitance is under %g pF" % 0.06)
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
    comps, nets, routes, clock_pins = read_def(routed["def"], set(drivers) | found["fanout"])
    macros = {}
    for name, views in (cfg.get("MACROS") or {}).items():
        lef = views["lef"][0]
        macros[name] = macro_pins(os.path.join(cfg_dir, lef[5:]) if lef.startswith("dir::") else lef)

    def findable(inst):
        """The ECO step escapes brackets before looking an instance up."""
        return inst in comps and comps[inst][4] == re.sub(r"([\[\]])", r"\\\1", inst)

    inserts, skipped, reroute = [], [], args.reroute
    if run != base:
        # The earlier ECO's buffers. One in front of a cell's input (a fanout
        # or long-net fix) only holds on a reroute that drops the old diodes;
        # buffers after a driver or at a macro pin do not need one.
        inserts = json.load(open(os.path.join(run, "resolved.json"))).get("INSERT_ECO_BUFFERS") or []
        # one buffer per target: an older version of this script added a
        # second one after a driver that still failed, chaining the two
        inserts = list({b["target"]: b for b in reversed(inserts)}.values())[::-1]

        def before_input(b):
            inst, _, pin = b["target"].rpartition("/")
            return pin not in DRIVER_PINS and not (inst in comps and comps[inst][0] in macros)
        reroute = reroute or any(before_input(b) for b in inserts)
    # macro and halo boxes, where a buffer cannot go
    halo = float(cfg.get("FP_MACRO_HORIZONTAL_HALO") or 0)
    core = cfg.get("CORE_AREA") or [-1e9, -1e9, 1e9, 1e9]
    keepout = []
    for inst, comp in comps.items():
        if comp[0] in macros:
            (w, h), _ = macros[comp[0]]
            if comp[3] in ("E", "W", "FE", "FW"):
                w, h = h, w
            keepout.append((comp[1] - halo, comp[2] - halo, comp[1] + w + halo, comp[2] + h + halo))

    # Slew seen only at the loads of a net: buffer halfway along its route
    # to the farthest such load, unless its driver is fixed below anyway.
    long_nets = {}
    for pin in found["slew"]:
        inst, _, name = pin.rpartition("/")
        if name in DRIVER_PINS or inst not in comps or "__diode" in comps[inst][0]:
            continue
        conns = nets.get(pin, [])
        driver = next(((i, p) for i, p in conns if p in DRIVER_PINS and i != "PIN"),
                      next(((i, p) for i, p in conns if i == "PIN"), None))
        if driver and f"{driver[0]}/{driver[1]}" not in drivers and findable(inst):
            long_nets.setdefault(driver, []).append(pin)
    for (dinst, dpin), loads in sorted(long_nets.items()):
        start = comps[dinst][1:3] if dinst in comps else None
        if start is None:
            skipped.append(f"{loads[0]} (driven by port {dpin})")
            continue
        best = None
        for pin in loads:
            got = path_midpoint(routes.get(pin, []), start, comps[pin.rpartition("/")[0]][1:3])
            if got and (best is None or got[1] > best[1]):
                best = (got[0], got[1], pin)
        at = free_point(best[0], keepout, core) if best else None
        if at is None:
            skipped.append(f"{loads[0]} (no routed path, or no free place near its midpoint)")
            continue
        cell = args.clock_buffer if best[2] in clock_pins else args.long_buffer
        inserts.append({"target": best[2], "buffer": cell, "placement": at})
        reroute = True
        print(f"long net: {dinst}/{dpin} -> {best[2]}, {best[1]:.0f} um routed; buffer at {at}")

    for pin in drivers:
        inst, _, name = pin.rpartition("/")
        if inst not in comps or comps[inst][0] in macros or name not in DRIVER_PINS:
            if not any(pin in loads for loads in long_nets.values()):
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
            # beside the driver: left to itself the ECO step puts the buffer
            # at the mean of the driver and its loads, and a small driver
            # kept most of a long net (FP16 tile: 0.058 pF on a 0.029 pF cell).
            # A weak driver gets the smallest buffer, which finds a site beside
            # it in a crowded row where a buf_4 was legalised 150 um away. It
            # can drive whatever the weak driver could (buf_1: 0.081 pF).
            if found["cap_limit"].get(pin, 1.0) < WEAK_DRIVER_PF and cell == args.buffer:
                cell = args.near_buffer
            at = [round(comps[inst][1], 3), round(comps[inst][2], 3)]
            earlier = next((b for b in inserts if b["target"] == pin), None)
            if earlier:
                earlier["placement"] = at
                earlier["buffer"] = cell
            else:
                inserts.append({"target": pin, "buffer": cell, "placement": at})
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
