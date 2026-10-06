# The v2 OpenFrame chip's core (superfloat_openframe: 4 SF16 core tiles,
# the pin bus, dispatcher and shared icache) on GT3, as v3/gt2n_v2chip/v2_chip:
# the tile hardened separately (designs/gt3/v2_tile, run TILE_VARIANT) and
# placed as a macro, no pad ring. Die from the tile LEF (chip_size.py: gap
# 6 um, logic strip 30 um, as at 2 nm). Clock from CLK_PERIOD_PS.
export DESIGN_NICKNAME = v2_chip
export DESIGN_NAME     = superfloat_openframe
export PLATFORM        = gt3
export VERILOG_FILES   = $(DESIGN_HOME)/src/v2chip/chip_top.v
export SDC_FILE        = $(DESIGN_HOME)/$(PLATFORM)/$(DESIGN_NICKNAME)/constraint.sdc
export PDN_TCL         = $(DESIGN_HOME)/$(PLATFORM)/$(DESIGN_NICKNAME)/pdn.tcl
export SYNTH_BLACKBOXES = core_tile
export TILE_VARIANT ?= p1000
TILE = $(DESIGN_HOME)/../results/gt3/v2_tile/$(TILE_VARIANT)
export ADDITIONAL_LEFS = $(TILE)/core_tile.lef
export ADDITIONAL_LIBS = $(TILE)/core_tile_typ.lib
export ADDITIONAL_GDS  = $(TILE)/6_final.gds
export DIE_AREA  = 0 0 264 288
export CORE_AREA = 2 2 262 286
export MACRO_PLACEMENT_TCL = $(DESIGN_HOME)/$(PLATFORM)/$(DESIGN_NICKNAME)/macro_place.tcl
export MACRO_PLACE_HALO = 4 4
export PLACE_DENSITY     = 0.60
export TNS_END_PERCENT   = 100
export MAX_ROUTING_LAYER = M10
export TILE_GAP   = 6
export TILE_STRIP = 30
