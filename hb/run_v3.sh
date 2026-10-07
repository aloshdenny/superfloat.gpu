#!/bin/bash
# One GEMM launch on the v3 matrix tiles of one format:
#   hb/run_v3.sh <sf16|fp16|bf16>[_m2|_a4] <launch name>      (e.g. sf16 fc1_t32)
# The launch is $V3L/<fmt>/<name>.npz (sw/v3/prepare_v3.py); the result is
# appended to $RUNS/v3_<fmt>.jsonl.
MC=${MC:-/root/hb/bsg_manycore}; ROOT=${ROOT:-/root/sfgpu}; RUNS=${RUNS:-/root/runs}; V3L=${V3L:-/root/v3launches}
fmt=$1; name=$2
d=$RUNS/${MACH:-v3}_$fmt/$name
rm -rf $d && mkdir -p $d && cd $d
# fmt: <sf16|fp16|bf16>[_m2][a4|_a4]; MACH selects the machine family
# (v3: hashing off, v3i: IPOLY hashing on)
base=${fmt%%_*}
case "$fmt" in *a4) V3L=${V3L}_a4 ;; esac          # 4 x 4 tiles: launches laid out for NA 4
python3 $ROOT/hb/sw/v3/gen_v3.py $V3L/$base/$name.npz launch.h
cp $ROOT/hb/sw/v3/main.c $ROOT/hb/sw/v3/Makefile .
t0=$(date +%s.%N)
make main.run BSG_MANYCORE_DIR=$MC SF_FMT=$fmt MACH=${MACH:-v3} > run.log 2>&1
rc=$?
t1=$(date +%s.%N)
python3 $ROOT/hb/parse_run.py run.log $fmt $name $rc $(echo "$t1 - $t0" | bc) >> $RUNS/${MACH:-v3}_$fmt.jsonl
rm -f main.nbf *.o *.a main.riscv launch.h
