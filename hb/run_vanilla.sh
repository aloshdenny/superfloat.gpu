#!/bin/bash
# The vanilla-core FP32 baseline (sw/vanilla) for one FP16 launch's operands:
#   hb/run_vanilla.sh <launch name>      -> $RUNS/vanilla.jsonl
MC=${MC:-/root/hb/bsg_manycore}; ROOT=${ROOT:-/root/sfgpu}; RUNS=${RUNS:-/root/runs}
name=$1
d=$RUNS/vanilla/$name
rm -rf $d && mkdir -p $d && cd $d
python3 $ROOT/hb/sw/vanilla/gen_vanilla.py $ROOT/test/gpt2/launches/fp16/$name.npz launch.h
cp $ROOT/hb/sw/vanilla/main.c $ROOT/hb/sw/vanilla/Makefile .
t0=$(date +%s.%N)
make main.run BSG_MANYCORE_DIR=$MC > run.log 2>&1
rc=$?
t1=$(date +%s.%N)
python3 $ROOT/hb/parse_run.py run.log vanilla $name $rc $(echo "$t1 - $t0" | bc) >> $RUNS/vanilla.jsonl
rm -f main.nbf *.o *.a
