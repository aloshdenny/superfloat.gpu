#!/usr/bin/env python3
"""Post-route ECO for residual max-slew / max-cap violations in a core_tile run.

Classic LibreLane repairs slew and capacitance before detailed routing only.
A few long nets can still exceed their driver's limit once real parasitics
(coupling included) are extracted. This script reads a finished run's
signoff checks in every corner, collects each driver pin with a slew or cap
violation, and writes an ECO config that inserts a buffer after each one,
re-routes the changed nets, and re-runs the full signoff sequence, starting
from the routed state saved before fill insertion.

usage: ./eco_fix.py runs/RUN_... [buffer_cell]
Writes eco_<run>.json next to this script and prints the command to run it.
"""
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
    sta = sorted(glob.glob(os.path.join(run, "*-openroad-stapostpnr")))[-1]
    drivers = set()
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
    return sorted(drivers)


def main():
    run = sys.argv[1].rstrip("/")
    buffer = sys.argv[2] if len(sys.argv) > 2 else "sky130_fd_sc_hd__buf_4"
    pre_fill = sorted(glob.glob(os.path.join(run, "*-checker-wirelength", "state_out.json")))
    if not pre_fill:
        sys.exit(f"{run}: no routed state before fill insertion")
    drivers = violating_drivers(run)
    if not drivers:
        sys.exit(f"{run}: no slew/cap violations; nothing to do")

    cfg = json.load(open(os.path.join(HERE, "config.json")))
    cfg["meta"] = {"version": 2, "flow": ECO_FLOW}
    cfg["INSERT_ECO_BUFFERS"] = [{"target": d, "buffer": buffer} for d in drivers]
    name = os.path.basename(run)
    out = os.path.join(HERE, f"eco_{name}.json")
    json.dump(cfg, open(out, "w"), indent=4)

    print(f"{len(drivers)} driver pins: {' '.join(drivers)}")
    print(f"wrote {out}")
    print("run from the librelane checkout's nix-shell:")
    print(f"  python3 -m librelane --pdk-root $HOME/.ciel {out} "
          f"--with-initial-state {os.path.abspath(pre_fill[-1])} --run-tag {name}_eco")


if __name__ == "__main__":
    main()
