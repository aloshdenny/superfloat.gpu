#!/bin/bash
# worker.sh <id>: pop "<variant> <period_ps> <power 0|1>" lines off the top of
# /root/v3/q2.txt (under a lock, so the file can be edited while workers run)
# until it is empty: run_one.sh, then gl_power.sh if power is 1. Start N of
# these for N slots. PLATFORM as setup.sh. Waits while the disk has under
# 8 GB free; after each run, keeps only its globally routed block
# (5_1_grt.odb/.sdc, enough to redo the reports) to save disk.
Q=/root/v3/q2.txt; id=$1
F=/OpenROAD-flow-scripts/flow
while true; do
  while [ $(df --output=avail -B1G / | tail -1) -lt 8 ]; do sleep 60; done
  line=$(flock /root/v3/q2.lock bash -c "l=\$(head -n1 $Q); [ -n \"\$l\" ] && { sed -i 1d $Q || l=; }; echo \"\$l\"")
  [ -z "$line" ] && break
  set -- $line
  echo "START $1 $2 $(date +%T) w$id" >> /root/v3/done.txt
  /root/v3/run_one.sh $1 $2
  [ "$3" = 1 ] && /root/v3/gl_power.sh $1 $2 > /root/v3/logs/$1_$2_power.log 2>&1
  echo "DONE $1 $2 $(date +%T) w$id" >> /root/v3/done.txt
  find $F/results/${PLATFORM:-gt2n}/v3_$1/p$2 -type f ! -name "5_1_grt.odb" ! -name "5_1_grt.sdc" -delete
  rm -rf $F/objects/${PLATFORM:-gt2n}/v3_$1/p$2
done
echo "WORKER $id EMPTY $(date +%T)" >> /root/v3/done.txt
