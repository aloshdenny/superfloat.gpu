# The v2 SF16 core tile on NanGate45, as v3/gt2n_v2chip/v2_tile but on ORFS's
# own nangate45 platform and its power grid (metal1/metal4/metal7, metal7
# stripes as the block's pins). Signal routing metal2-metal7, so the chip can
# run its metal8 power stripes and route over the tiles on metal8-metal10:
# the platform's config.mk sets MAX_ROUTING_LAYER with a plain assignment
# after this file, so it is overridden here. Clock from CLK_PERIOD_PS (the
# SDC is in ns).
export DESIGN_NICKNAME = v2_tile
export DESIGN_NAME     = core_tile
export PLATFORM        = nangate45
export VERILOG_FILES   = $(DESIGN_HOME)/src/v2chip/core_tile.v
export SDC_FILE        = $(DESIGN_HOME)/$(PLATFORM)/$(DESIGN_NICKNAME)/constraint.sdc
export CORE_UTILIZATION  = 50
export CORE_ASPECT_RATIO = 1
export CORE_MARGIN       = 2
export PLACE_DENSITY     = 0.60
export TNS_END_PERCENT   = 100
override MAX_ROUTING_LAYER = metal7
export MAX_ROUTING_LAYER
