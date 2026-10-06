# The v2 SF16 core tile on GT3, as v3/gt2n_v2chip/v2_tile but for the
# platform and its own pdn.tcl (block power pins on M11, above the tile's
# M2-M10 routing). Clock from CLK_PERIOD_PS (default 650 ps, as at 2 nm).
export DESIGN_NICKNAME = v2_tile
export DESIGN_NAME     = core_tile
export PLATFORM        = gt3
export VERILOG_FILES   = $(DESIGN_HOME)/src/v2chip/core_tile.v
export SDC_FILE        = $(DESIGN_HOME)/$(PLATFORM)/$(DESIGN_NICKNAME)/constraint.sdc
export PDN_TCL         = $(DESIGN_HOME)/$(PLATFORM)/$(DESIGN_NICKNAME)/pdn.tcl
export CORE_UTILIZATION  = 50
export CORE_ASPECT_RATIO = 1
export CORE_MARGIN       = 2
export PLACE_DENSITY     = 0.60
export TNS_END_PERCENT   = 100
export MAX_ROUTING_LAYER = M10
