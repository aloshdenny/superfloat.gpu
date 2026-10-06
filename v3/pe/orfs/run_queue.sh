#!/bin/bash
# run_queue.sh: as run_all.sh, over "<variant> <period_ps> <power 0|1>" lines
# appended to /root/v3/queue.txt (tail -f, so jobs can be added while it
# runs; stop the session when the queue is drained). Four slots, 8 cores
# each: run_one.sh, then gl_power.sh if power is 1. PLATFORM as setup.sh.
touch /root/v3/queue.txt
tail -n +1 -f /root/v3/queue.txt | xargs -P 4 -L 1 bash -c \
  '/root/v3/run_one.sh $0 $1; [ "$2" = 1 ] && /root/v3/gl_power.sh $0 $1 > /root/v3/logs/$0_$1_power.log 2>&1; echo "DONE $0 $1 $(date +%T)" >> /root/v3/done.txt'
