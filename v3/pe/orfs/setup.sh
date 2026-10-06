#!/bin/bash
# S2 on a pod: one ORFS design per v3 block variant (v3_variants.sv via
# sv2v as v3_blocks.v). Clock period from CLK_PERIOD_PS (FLOW_VARIANT names
# the run), so one design serves every target. PLATFORM: gt2n (default) or
# gt3; MAX_ROUTING_LAYER M10 on both.
#   [PLATFORM=gt3] setup.sh <variant ...>
set -euo pipefail
F=/OpenROAD-flow-scripts/flow
P=${PLATFORM:-gt2n}
mkdir -p $F/designs/src/v3
cp /root/v3/v3_blocks.v $F/designs/src/v3/
for v in "$@"; do
  d=$F/designs/$P/v3_$v; mkdir -p $d
  cat > $d/config.mk <<MK
export DESIGN_NICKNAME = v3_$v
export DESIGN_NAME     = blk_$v
export PLATFORM        = $P
export VERILOG_FILES   = \$(DESIGN_HOME)/src/v3/v3_blocks.v
export SDC_FILE        = \$(DESIGN_HOME)/\$(PLATFORM)/\$(DESIGN_NICKNAME)/constraint.sdc
export CORE_UTILIZATION  = 50
export CORE_ASPECT_RATIO = 1
export CORE_MARGIN       = 2
export PLACE_DENSITY     = 0.60
export TNS_END_PERCENT   = 100
export MAX_ROUTING_LAYER = M10
MK
  cat > $d/constraint.sdc <<SDC
current_design blk_$v
set clk_period [expr {[info exists ::env(CLK_PERIOD_PS)] ? \$::env(CLK_PERIOD_PS) : 500}]
set clk_io_pct 0.2
create_clock -name clk -period \$clk_period [get_ports clk]
set non_clock_inputs [all_inputs -no_clocks]
set_input_delay [expr \$clk_period * \$clk_io_pct] -clock clk \$non_clock_inputs
set_output_delay [expr \$clk_period * \$clk_io_pct] -clock clk [all_outputs]
SDC
done
echo "set up: $*"
