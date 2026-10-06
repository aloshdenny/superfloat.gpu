#!/bin/bash
# report.sh <variant> <period_ps>: area, cells, flops and register-to-register
# timing of the globally routed block (estimated parasitics from the global
# route, as for GT2N, which has no extraction rules), into
# /root/v3/reports/<variant>_<ps>.txt. PLATFORM as setup.sh; the report is in
# the platform's time unit (TIME_UNIT line: ps on gt2n, ns on nangate45).
v=$1; ps=$2
F=/OpenROAD-flow-scripts/flow
P=${PLATFORM:-gt2n}
R=$F/results/$P/v3_$v/p$ps
case $P in nangate45) U=ns; D=4 ;; *) U=ps; D=2 ;; esac
mkdir -p /root/v3/reports
cd $F
export CLK_PERIOD_PS=$ps
cat > /tmp/rep_${v}_$ps.tcl <<TCL
source \$::env(SCRIPTS_DIR)/load.tcl
load_design 5_1_grt.odb [expr {[file exists $R/5_1_grt.sdc] ? "5_1_grt.sdc" : "4_cts.sdc"}]
estimate_parasitics -global_routing
puts "VARIANT $v PERIOD_PS $ps"
puts "TIME_UNIT $U"
report_design_area
set ncell 0; set nreg 0
foreach i [[ord::get_db_block] getInsts] {
  set m [\$i getMaster]
  if {[\$m isFiller] || [string match -nocase "*tap*" [\$m getName]]} { continue }
  incr ncell
  if {[\$m isSequential]} { incr nreg }
}
puts "CELLS \$ncell REGS \$nreg"
puts "REG2REG"
report_checks -from [all_registers -clock_pins] -to [all_registers -data_pins] -format end -digits $D
report_checks -from [all_registers -clock_pins] -to [all_registers -data_pins] -digits $D
puts "ALLPATHS"
report_worst_slack -max -digits $D
report_tns -digits $D
write_verilog /root/v3/netlists/${v}_$ps.v
TCL
mkdir -p /root/v3/netlists
# The platform's variables (PLATFORM_DIR and the libs) come from the flow's Makefile.
make DESIGN_CONFIG=designs/$P/v3_$v/config.mk FLOW_VARIANT=p$ps \
  RUN_SCRIPT=/tmp/rep_${v}_$ps.tcl run > /root/v3/reports/${v}_$ps.txt 2>&1
