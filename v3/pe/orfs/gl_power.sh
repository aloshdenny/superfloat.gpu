#!/bin/bash
# gl_power.sh <variant> <period_ps>: gate-level run of the globally routed
# block on the GPT-2 power stimulus (power_stim.py), checked against the RTL
# on the same stimulus, then OpenSTA power from the run's switching activity
# with global-route parasitics. Report: /root/v3/reports/<variant>_<ps>_power.txt
set -uo pipefail
v=$1; ps=$2
F=/OpenROAD-flow-scripts/flow
V=/root/v3
W=$V/gl/${v}_$ps; mkdir -p $W; cd $W
read L LINES FROM TO IW CW WV < <(python3 - <<PY
import json
m = json.load(open("$V/stim/meta.json"))["variants"]["$v"]
import re
src = open("$V/v3_blocks.v").read()
mod = re.search(r"module blk_$v\b.*?endmodule", src, re.S).group(0)
iw = int(re.search(r"input wire \[(\d+):0\] a_west", mod).group(1)) + 1
cw = int(re.search(r"input wire \[(\d+):0\] psum_north", mod).group(1)) + 1
print(m["L"], m["lines"], m["dump_from"], m["dump_to"], iw // 8, cw // 8, m.get("wave", 0))
PY
)
cp $V/stim/$v.txt stim.txt
[ -f $V/gt2n_cells.v ] || python3 $V/lib2v.py $F/platforms/gt2n/lib/gt2_6t_w31_lvt_tt_0p7v25c.lib $V/gt2n_cells.v
DEFS="-DTOP=blk_$v -DIW=$IW -DCW=$CW -DN=8 -DPERIOD=$ps -DDUMP_FROM=$FROM -DDUMP_TO=$TO"
[ "$WV" = 1 ] && DEFS="$DEFS -DWAVE"
mkdir -p rtl && (cd rtl && cp ../stim.txt . && iverilog -g2012 -s tb_block $DEFS -o rtl.vvp $V/v3_blocks.v $V/tb_gl.sv && vvp -n rtl.vvp > /dev/null && rm -f act.vcd)
iverilog -g2012 -s tb_block $DEFS -o gl.vvp $V/gt2n_cells.v $V/netlists/${v}_$ps.v $V/tb_gl.sv || exit 1
vvp -n gl.vvp > gl.log 2>&1 || exit 1
python3 - <<PY > equiv.txt
a = open("rtl/out.txt").read().split(); b = open("out.txt").read().split()
n = sum(1 for x in a if "x" not in x)
bad = sum(1 for x, y in zip(a, b) if "x" not in x and x != y)
print(f"EQUIV {n - bad}/{n} defined RTL output lines match the gate level")
PY
cat equiv.txt
cat > power.tcl <<TCL
source \$::env(SCRIPTS_DIR)/load.tcl
load_design 5_1_grt.odb [expr {[file exists \$::env(RESULTS_DIR)/5_1_grt.sdc] ? "5_1_grt.sdc" : "4_cts.sdc"}]
estimate_parasitics -global_routing
read_vcd -scope tb_block/dut $W/act.vcd
puts "VARIANT $v PERIOD_PS $ps WINDOW \$::env(WIN_CYCLES) cycles"
report_power -digits 6
TCL
cd $F
WIN_CYCLES=$((TO - FROM)) CLK_PERIOD_PS=$ps make DESIGN_CONFIG=designs/gt2n/v3_$v/config.mk FLOW_VARIANT=p$ps \
  RUN_SCRIPT=$W/power.tcl run > $V/reports/${v}_${ps}_power.txt 2>&1
cat $W/equiv.txt >> $V/reports/${v}_${ps}_power.txt
rm -f $W/act.vcd $W/gl.vvp
grep -E "^Total|EQUIV" $V/reports/${v}_${ps}_power.txt
