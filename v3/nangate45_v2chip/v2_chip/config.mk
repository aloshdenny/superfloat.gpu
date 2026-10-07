# The v2 OpenFrame chip's core (superfloat_openframe: 4 SF16 core tiles,
# the pin bus, dispatcher and shared icache) on NanGate45, as
# v3/gt2n_v2chip/v2_chip: the tile hardened separately (designs/nangate45/
# v2_tile, run TILE_VARIANT) and placed as a macro, no pad ring. Die from the
# tile LEF (chip_size.py with TILE_GAP and TILE_STRIP below; 2 nm used 6
# and 30 um). The core reaches the die's left and right edges (2 um inside it at 2 nm; 1 um at
# top and bottom, so the bottom row's VSS rail stays on the die): with the
# 4 um left channel that a 2 um inset leaves, pdngen cannot strap the rows
# between the core edge and the tiles (PDN-0179). Power: pdn.tcl (the
# platform's grid plus metal8 stripes over the tiles' metal7 pins). Clock
# from CLK_PERIOD_PS (the SDC is in ns).
export DESIGN_NICKNAME = v2_chip
export DESIGN_NAME     = superfloat_openframe
export PLATFORM        = nangate45
export VERILOG_FILES   = $(DESIGN_HOME)/src/v2chip/chip_top.v
export SDC_FILE        = $(DESIGN_HOME)/$(PLATFORM)/$(DESIGN_NICKNAME)/constraint.sdc
export PDN_TCL         = $(DESIGN_HOME)/$(PLATFORM)/$(DESIGN_NICKNAME)/pdn.tcl
export SYNTH_BLACKBOXES = core_tile
export TILE_VARIANT ?= p1500
TILE = $(DESIGN_HOME)/../results/nangate45/v2_tile/$(TILE_VARIANT)
export ADDITIONAL_LEFS = $(TILE)/core_tile.lef
export ADDITIONAL_LIBS = $(TILE)/core_tile_typ.lib
export ADDITIONAL_GDS  = $(TILE)/6_final.gds
export DIE_AREA  = 0 0 1450 1510
export CORE_AREA = 0 1 1450 1509
export MACRO_PLACEMENT_TCL = $(DESIGN_HOME)/$(PLATFORM)/$(DESIGN_NICKNAME)/macro_place.tcl
export MACRO_PLACE_HALO = 4 4
export PLACE_DENSITY     = 0.60
# The chip's own logic (30,000 um2 of cells in the strip and the channels
# around four 694 um tiles) makes global placement diverge (GPL-0307) at the
# default step; a smaller maximum step fixes it.
export MAX_PLACE_STEP_COEF   = 1.02
export GLOBAL_PLACEMENT_ARGS = -max_phi_coef 1.02
export TNS_END_PERCENT   = 100
# 45 nm: the 2 nm rule (gap 6, strip 30) left 30,000 um2 of chip logic
# with nowhere to route (global route overflow on metal7-metal9, GRT-0116,
# 2026-10-07): 20 um channels and an 80 um strip.
export TILE_GAP   = 20
export TILE_STRIP = 80
