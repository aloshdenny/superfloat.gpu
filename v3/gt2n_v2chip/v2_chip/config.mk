# The v2 OpenFrame chip's core (superfloat_openframe: 4 SF16 core tiles,
# the pin bus, dispatcher and shared icache) on GT2N, with the tile
# hardened separately (designs/gt2n/v2_tile) and placed as a macro. No pad
# ring: GT2N has no I/O cells.
export DESIGN_NICKNAME = v2_chip
export DESIGN_NAME     = superfloat_openframe
export PLATFORM        = gt2n
export VERILOG_FILES   = $(DESIGN_HOME)/src/v2chip/chip_top.v
export SDC_FILE        = $(DESIGN_HOME)/$(PLATFORM)/$(DESIGN_NICKNAME)/constraint.sdc
export SYNTH_BLACKBOXES = core_tile
TILE = $(DESIGN_HOME)/../results/gt2n/v2_tile/base
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
