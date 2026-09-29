import glob, json, os, sys

SP = os.path.dirname(os.path.abspath(__file__))
KEYS_ZERO = ["design__max_slew_violation__count", "design__max_cap_violation__count",
             "design__max_fanout_violation__count", "magic__drc_error__count",
             "klayout__drc_error__count", "design__lvs_error__count",
             "antenna__violating__nets", "route__drc_errors"]

rows = []
for d in sorted(glob.glob(f"{SP}/h_*")):
    f = f"{d}/runs/r/final/metrics.json"
    if not os.path.exists(f):
        rows.append((os.path.basename(d), None)); continue
    m = json.load(open(f))
    cfg = json.load(open(f"{d}/config.json"))
    T = cfg["CLOCK_PERIOD"]
    ss = {k.split("corner:")[1]: v for k, v in m.items() if k.startswith("timing__setup__ws__corner:")}
    hs = {k.split("corner:")[1]: v for k, v in m.items() if k.startswith("timing__hold__ws__corner:")}
    ws = min(ss.values()); hw = min(hs.values())
    rows.append((os.path.basename(d), dict(
        T=T, area=m["design__instance__area__stdcell"], util=m["design__instance__utilization"],
        ws=ws, ws_corner=min(ss, key=ss.get), hold=hw, fmax=1000.0 / (T - ws),
        ws_tt=ss.get("nom_tt_025C_1v80"), fmax_tt=1000.0 / (T - ss["nom_tt_025C_1v80"]),
        power=m.get("power__total"), cells=m.get("design__instance__count__stdcell"),
        viol={k.split("__")[1]: m.get(k) for k in KEYS_ZERO})))

print(f"{'run':14s} {'T(ns)':>5s} {'area um2':>9s} {'util':>5s} {'WS ss(ns)':>9s} {'Fmax ss':>8s} {'Fmax tt':>8s} {'hold':>6s} {'P flow(mW)':>10s}  violations")
for name, r in rows:
    if r is None:
        print(f"{name:14s} (not finished)"); continue
    bad = {k: v for k, v in r["viol"].items() if v}
    print(f"{name:14s} {r['T']:5.0f} {r['area']:9.1f} {r['util']:5.3f} {r['ws']:9.3f} {r['fmax']:8.2f} {r['fmax_tt']:8.2f} {r['hold']:6.3f} {1000*r['power']:10.4f}  {bad if bad else 'all 0'}")
json.dump({n: r for n, r in rows}, open(f"{SP}/bench.json", "w"), indent=1)
