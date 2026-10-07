#!/bin/bash
# Wire the SuperFloat tiles into a bsg_manycore checkout (run once per checkout):
#   hb/setup_pod.sh <bsg_manycore dir> <this repo's root>
# 1. arch_filelist.mk includes hb/sf_filelist.mk (adapter, hetero socket, v1 RTL).
# 2. Tile types: upstream's hetero_type_vec_p (an unpacked array parameter) does
#    not elaborate in Verilator 5 when overridden, and spmd_testbench never sets
#    it. Instead the tile array takes the type of each tile in row SF_ACCEL_ROW
#    from SF_ACCEL_TYPE when those are defined; other machines are unchanged.
# 3. Makefile.verilator passes a machine's SF_MACHINE_DEFINES to Verilator.
# 4. test.cpp waits for reset to rise before arming assertions (below).
# 5. The machines in hb/machines (v1 tiles: sf_4x2_*, v3 matrix tiles: v3_4x2_*).
set -e
MC=$(cd "$1" && pwd); ROOT=$(cd "$2" && pwd)
cd $MC
git checkout -- testbenches/common/v/spmd_testbench.sv
grep -q sf_filelist.mk machines/arch_filelist.mk || \
  printf '\nSF_HB_DIR ?= %s\ninclude $(SF_HB_DIR)/hb/sf_filelist.mk\n' "$ROOT" >> machines/arch_filelist.mk
F=v/bsg_manycore_tile_compute_array_ruche.sv
grep -q SF_ACCEL_TYPE $F || python3 - $F <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = "        ,.hetero_type_p(hetero_type_vec_p[(r*subarray_num_tiles_x_p)+c])\n"
assert old in t
t = t.replace(old, "`ifdef SF_ACCEL_TYPE\n        ,.hetero_type_p((r == `SF_ACCEL_ROW) ? `SF_ACCEL_TYPE : 0)\n`else\n" + old + "`endif\n")
open(p, "w").write(t)
PY
# 4. testbenches/common/v/test.cpp (the Verilator main) turns assertions on once
#    reset_o reads 0, but under Verilator's 2-state start reset_o is 0 before the
#    reset generator has raised it, so the tie-off assertions fire on cycle 1
#    (upstream's own hello fails this way). Wait for reset to rise first.
F=testbenches/common/v/test.cpp
grep -q "wait for reset to rise" $F || python3 - $F <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = "  while(tb->reset_o == 1) {"
assert old in t
t = t.replace(old, "  // wait for reset to rise (Verilator starts every register at 0)\n"
              "  for (int i = 0; i < 100000 && tb->reset_o == 0; i++) {\n"
              "    bsg_timekeeper::next();\n    tb->eval();\n  }\n\n" + old, 1)
open(p, "w").write(t)
PY
F=machines/Makefile.verilator
grep -q SF_MACHINE_DEFINES $F || sed -i 's|^\t\$(eval VERILATOR_DEFINES += +define+BSG_MACHINE_HETERO_TYPE_VEC=.*$|&\n\t$(eval VERILATOR_DEFINES += $(SF_MACHINE_DEFINES))|' $F
grep -n SF_MACHINE_DEFINES $F
for m in $(cd $ROOT/hb/machines && ls -d */ | tr -d /); do
  mkdir -p machines/$m
  cp $ROOT/hb/machines/$m/Makefile.machine.include machines/$m/
done
git diff --stat
echo wired
