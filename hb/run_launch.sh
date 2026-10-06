#!/bin/bash
# One GPT-2 launch on the HammerBlade machine of one format:
#   hb/run_launch.sh <sf16|fp16|bf16>[_rb] <launch name>
# (_rb: the machine whose adapters have the read buffer)
# Builds the driver with the launch's data (sw/gen_launch.py), runs it on
# machines/sf_4x2_<fmt>/simsc, and appends the result to $RUNS/<fmt>.jsonl.
# MC (bsg_manycore), ROOT (this repo) and RUNS default to the pod's paths.
MC=${MC:-/root/hb/bsg_manycore}; ROOT=${ROOT:-/root/sfgpu}; RUNS=${RUNS:-/root/runs}
fmt=$1; name=$2
d=$RUNS/$fmt/$name
rm -rf $d && mkdir -p $d && cd $d
python3 $ROOT/hb/sw/gen_launch.py $ROOT/test/gpt2/launches/${fmt%_rb}/$name.npz launch.h
cp $ROOT/hb/sw/main.c $ROOT/hb/sw/Makefile .
t0=$(date +%s.%N)
make main.run BSG_MANYCORE_DIR=$MC SF_FMT=$fmt > run.log 2>&1
rc=$?
t1=$(date +%s.%N)
python3 $ROOT/hb/parse_run.py run.log $fmt $name $rc $(echo "$t1 - $t0" | bc) >> $RUNS/$fmt.jsonl
rm -f main.nbf *.o *.a
