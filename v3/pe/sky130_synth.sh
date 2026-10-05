#!/bin/bash
# S2 at SKY130, synthesis area only: Yosys + ABC on sky130_fd_sc_hd (typical
# corner), mapped at 10 ns. Runs inside LibreLane's nix-shell on the build
# server:
#   sky130_synth.sh <dir with v3_blocks.v> <variant ...>
# No timing here: without buffering, the block's 1,024-pin weight-control
# nets set the worst path, and ABC maps the same netlist at 2 ns as at 10 ns.
# Timing and power come from the placed and routed GT2N blocks.
set -euo pipefail
D=$(cd "$1" && pwd); shift
LIB=$HOME/.ciel/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
cd "$D"; mkdir -p sky130
for v in "$@"; do
  for T in 10000; do
    o=sky130/${v}_$T
    cat > $o.ys <<YS
read_verilog -sv v3_blocks.v
synth -top blk_$v -flatten
dfflibmap -liberty $LIB
abc -liberty $LIB -D $T
opt_clean -purge
tee -o $o.stat stat -liberty $LIB
write_verilog -noattr $o.v
YS
    yosys -q -l $o.ylog $o.ys >/dev/null
    echo "$v area $(grep -E 'Chip area' $o.stat | tail -1 | awk '{print $NF}') cells $(grep -E 'Number of cells' $o.stat | tail -1 | awk '{print $NF}') flops $(grep -E 'sky130_fd_sc_hd__(e?dfxtp|dfrtp|dfstp|dfbbp|edfxbp|dfxbp)' $o.stat | awk '{s+=$1} END {print s}')"
  done
done
