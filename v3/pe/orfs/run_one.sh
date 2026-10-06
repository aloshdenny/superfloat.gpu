#!/bin/bash
# run_one.sh <variant> <period_ps>: ORFS through global routing, then report.sh.
# Log /root/v3/logs/<variant>_<ps>.log, ending FLOW_EXIT <code>. PLATFORM as setup.sh.
v=$1; ps=$2; tag=p$ps
F=/OpenROAD-flow-scripts/flow
P=${PLATFORM:-gt2n}
mkdir -p /root/v3/logs
log=/root/v3/logs/${v}_$ps.log
cd $F
( export CLK_PERIOD_PS=$ps NUM_CORES=${NUM_CORES:-8}
  make DESIGN_CONFIG=designs/$P/v3_$v/config.mk FLOW_VARIANT=$tag grt &&
  /root/v3/report.sh $v $ps ) > $log 2>&1
echo "FLOW_EXIT $?" >> $log
