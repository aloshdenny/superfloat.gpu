#!/usr/bin/env python3
"""The SFHB line of a driver run (sw/main.c) as one JSON record.

  parse_run.py <run.log> <fmt> <name> <make exit code> <wall seconds>
"""
import json
import re
import sys

log, fmt, name, rc, wall = sys.argv[1:6]
text = open(log, errors="replace").read()
rec = {"name": name, "fmt": fmt, "make_rc": int(rc), "sim_seconds": round(float(wall), 1)}
m = re.search(r"SFHB (.*)", text)
if m:
    for k, v in re.findall(r"(\w+)=(\S+)", m.group(1)):
        rec[k] = int(v) if re.fullmatch(r"-?\d+", v) else v
rec["finish"] = ("BSG_FINISH" in text or "RECEIVED a finish packet" in text) and "BSG_FAIL" not in text
rec["timeout"] = "BSG_TIMEOUT" in text
rec["errors"] = len(re.findall(r"BSG_ERROR|\[sf_hb_accel\]|%Error|Assertion failed", text))
print(json.dumps(rec))
