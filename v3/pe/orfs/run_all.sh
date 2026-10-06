#!/bin/bash
# run_all.sh <period_ps> <power 0|1> <variant ...>: ORFS to global route for
# each variant, four at a time (8 cores each); with power 1, gate-level power
# at that period (gl_power.sh) after each flow. PLATFORM as setup.sh.
ps=$1; pw=$2; shift 2
printf "%s\n" "$@" | xargs -P 4 -I{} bash -c "/root/v3/run_one.sh {} $ps; [ $pw = 1 ] && /root/v3/gl_power.sh {} $ps > /root/v3/logs/{}_${ps}_power.log 2>&1"
echo "ALL_DONE $ps"
