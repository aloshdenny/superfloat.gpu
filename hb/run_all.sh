#!/bin/bash
# Every launch in a list, for each format, JOBS at a time:
#   hb/run_all.sh <names file> <fmt> [<fmt> ...]
# Results: $RUNS/<fmt>.jsonl (run_launch.sh). Machines must be built first.
HERE=$(cd $(dirname $0) && pwd)
names=$1; shift
for fmt in "$@"; do
  for n in $(cat $names); do echo "$fmt $n"; done
done | xargs -P ${JOBS:-7} -n 2 $HERE/run_launch.sh
