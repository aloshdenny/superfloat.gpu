#!/usr/bin/env python3
"""Post-route ECO for residual max-slew / max-cap violations in a core_tile run.

Classic LibreLane repairs slew and capacitance before detailed routing only.
A few long nets can still exceed their driver's limit once real parasitics
(coupling included) are extracted. This script reads a finished run's
signoff checks in every corner, collects each driver pin with a slew or cap
violation, and writes an ECO config that inserts a buffer after each one,
re-routes the changed nets, and re-runs the full signoff sequence, starting
from the routed state saved before fill insertion.

usage: ./eco_fix.py runs/RUN_... [--config config.json] [--buffer CELL]
                                  [--clock-buffer CELL]
--config is the harden config the run used, relative to this directory or
absolute (e.g. config_fp16.json, ../openframe/config.json). The ECO config
eco_<run>.json is written next to it; the command to run it is printed.

Only standard-cell output pins are buffered; a macro output pin (a tile's
port at chip level) is reported and skipped, since the buffer would be
placed from the macro's origin. Clock-tree drivers (CTS's clkbuf_* and
delaybuf_* instances) get --clock-buffer so clock nets stay on clock cells.
The IR-drop step is left out when the config disables it.
"""
import argparse
import glob
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DRIVER_PINS = {"X", "Y", "Q", "Q_N", "Z", "HI", "LO"}

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


def violating_drivers(run):
    """(driver pins to buffer, other violating pins that are not cell drivers)"""
    sta = sorted(glob.glob(os.path.join(run, "*-openroad-stapostpnr")))[-1]
    drivers = set()
    others = set()
    for rpt in glob.glob(os.path.join(sta, "*", "checks.rpt")):
        section = None
        for line in open(rpt):
            if line.startswith("max slew") or line.startswith("max capacitance"):
                section = "check"
                continue
            if line.startswith("max fanout") or line.startswith("===="):
                section = None
            if section and "(VIOLATED)" in line:
                pin = line.split()[0]
                inst, _, name = pin.rpartition("/")
                if inst and name in DRIVER_PINS:
                    drivers.add(pin)
                else:
                    others.add(pin)
    return sorted(drivers), sorted(others - drivers)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("run")
    ap.add_argument("--config", default="config.json")
    ap.add_argument("--buffer", default="sky130_fd_sc_hd__buf_4")
    ap.add_argument("--clock-buffer", default="sky130_fd_sc_hd__clkbuf_8")
    args = ap.parse_args()
    run = args.run.rstrip("/")
    buffer = args.buffer
    config = args.config if os.path.isabs(args.config) else os.path.join(HERE, args.config)
    pre_fill = sorted(glob.glob(os.path.join(run, "*-checker-wirelength", "state_out.json")))
    if not pre_fill:
        sys.exit(f"{run}: no routed state before fill insertion")
    drivers, others = violating_drivers(run)
    if others:
        print(f"not cell drivers (loads or macro pins), not buffered: {' '.join(others)}")
    if not drivers:
        sys.exit(f"{run}: no slew/cap violations on cell drivers; nothing to do")

    cfg = json.load(open(config))
    flow = [s for s in ECO_FLOW
            if not (s == "OpenROAD.IRDropReport" and cfg.get("RUN_IRDROP_REPORT") is False)]
    cfg["meta"] = {"version": 2, "flow": flow}

    def cell_for(pin):
        inst = pin.rpartition("/")[0]
        return args.clock_buffer if inst.startswith(("clkbuf", "delaybuf")) else buffer
    cfg["INSERT_ECO_BUFFERS"] = [{"target": d, "buffer": cell_for(d)} for d in drivers]
    name = os.path.basename(run)
    out = os.path.join(os.path.dirname(os.path.abspath(config)), f"eco_{name}.json")
    json.dump(cfg, open(out, "w"), indent=4)

    print(f"{len(drivers)} driver pins: {' '.join(drivers)}")
    print(f"wrote {out}")
    print("run from the librelane checkout's nix-shell:")
    print(f"  python3 -m librelane --pdk-root $HOME/.ciel {out} "
          f"--with-initial-state {os.path.abspath(pre_fill[-1])} --run-tag {name}_eco")


if __name__ == "__main__":
    main()
