#!/bin/bash
# OpenSTA power of a finished run_power.sh simulation.
#
#   power_sta.sh <sf16|fp16|bf16> <image dir>
#
# OpenSTA annotates pins from a VCD: a variable inside a cell instance's scope.
#   - Tile 0: dumped with its cells; Icarus names its scope
#     chip.gpu_inst.tiles[0].tile (the escaped instance name, unescaped).
#   - Top level: dumped as nets; vcd_pins.py rewrites them as the pins of
#     the cells on each net.
# Both blocks are analysed at nom_tt_025C_1v80 with their signoff SPEF and
# SDC (20 ns clock). Writes power_top.rpt, power_tile.rpt and power.json in
# <image dir>/sim/.
set -euo pipefail
FMT=$1
IMG=$(cd "$2" && pwd)
HERE=$(cd "$(dirname "$0")" && pwd)
LL=${LL:-$HOME/alosh/superfloat.gpu/librelane}
case $FMT in
  sf16) T1=RUN_2026-09-29_00-38-54_eco; C1=chip_20_eco2 ;;
  fp16) T1=fp16_10r_eco5_s; C1=chip_fp16_1_eco_s ;;
  bf16) T1=bf16_4_eco_s; C1=chip_bf16_2_eco4_s ;;
  *) echo "format must be sf16, fp16 or bf16" >&2; exit 1 ;;
esac
# TILE and CHIP name the signed-off runs (run_power.sh passes them on).
TILE=${TILE:-$LL/core_tile/runs/$T1}
CHIP=${CHIP:-$LL/openframe/runs/$C1}
PDK=${PDK:-$HOME/.ciel/ciel/sky130/versions/1689ac3f2dc763876eaf967227c7dfe831b031ae/sky130A}
TT=$PDK/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
STA=${STA:-sta}
cd "$IMG/sim"

python3 "$HERE/vcd_pins.py" "$CHIP/final/nl/openframe_project_wrapper.nl.v" power.vcd power_pins.vcd

cat > power_top.tcl <<EOF
read_liberty $TT
read_liberty $(ls "$TILE"/final/lib/nom_tt_025C_1v80/*.lib | head -1)
read_verilog $CHIP/final/nl/openframe_project_wrapper.nl.v
link_design openframe_project_wrapper
read_sdc $CHIP/final/sdc/openframe_project_wrapper.sdc
read_spef $CHIP/final/spef/nom/openframe_project_wrapper.nom.spef
read_vcd -scope tb_chip_power/dut power_pins.vcd
report_power
report_activity_annotation
EOF
cat > power_tile.tcl <<EOF
read_liberty $TT
read_verilog $TILE/final/nl/core_tile.nl.v
link_design core_tile
read_sdc $TILE/final/sdc/core_tile.sdc
read_spef $TILE/final/spef/nom/core_tile.nom.spef
read_vcd -scope {tb_chip_power/dut/chip.gpu_inst.tiles[0].tile} power.vcd
report_power
report_activity_annotation
EOF
"$STA" -no_splash -exit power_top.tcl > power_top.rpt 2>&1
"$STA" -no_splash -exit power_tile.tcl > power_tile.rpt 2>&1

python3 - "$FMT" <<'PY'
import json, re, sys
def parse(rpt):
    t = open(rpt).read()
    groups = {m[0].lower(): float(m[4]) for m in re.findall(r"^(Sequential|Combinational|Clock|Macro|Pad)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)", t, re.M)}
    total = float(re.search(r"^Total\s+\S+\s+\S+\s+\S+\s+(\S+)", t, re.M).group(1))
    ann = int(re.search(r"^vcd\s+(\d+)", t, re.M).group(1))
    un = int(re.search(r"^unannotated\s+(\d+)", t, re.M).group(1))
    return total, groups, ann, un
top, tg, ta, tu = parse("power_top.rpt")
tile, lg, la, lu = parse("power_tile.rpt")
log = open("sim.log").read()
m = re.search(r"(DONE|STOPPED) cycles=(\d+).*dump=(\d+)\.\.(\d+)", log)
out = dict(fmt=sys.argv[1], top_w=top, tile_w=tile, chip_w=top + 4 * tile, top_groups=tg, tile_groups=lg,
           top_annotated=[ta, tu], tile_annotated=[la, lu], dump_cycles=[int(m.group(3)), int(m.group(4))],
           corner="nom_tt_025C_1v80", clock_mhz=50.0)
json.dump(out, open("power.json", "w"), indent=1)
print(f"[power_sta] {sys.argv[1]}: top {top*1e3:.2f} mW, tile {tile*1e3:.2f} mW, chip {out['chip_w']*1e3:.1f} mW "
      f"(annotated top {ta}/{ta+tu}, tile {la}/{la+lu})")
PY
