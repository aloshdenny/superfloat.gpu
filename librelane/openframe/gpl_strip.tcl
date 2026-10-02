# Global placement of the chip's standard cells in the strip between the tile
# rows (OpenROAD.GlobalPlacementStrip in chip_flow.py; LibreLane's gpl.tcl
# otherwise).
#
# The strip is the only place every format's chip has room for its logic:
# FP16's tiles fill the core above and below it. With every row in place,
# RePlAce pushes the cells out of the strip through the macros: into the
# empty bands beside shorter tiles (2-7 mm nets), or, with those blocked,
# until it diverges. Here the rows outside the strip are removed for the
# placement and put back after it, so the cells are placed in the strip.
# Placement stops at an overflow of OVERFLOW: past it the strip-only run can
# diverge, and detailed placement legalizes the rest.
#
# The chip config sets the target density (PL_TARGET_DENSITY_PCT) at the
# strip's utilization, so the logic spreads over the whole strip. At 50% it
# bunched in the strip's middle: the shared-read lookup's fan-out took that
# 200 um to 7,600 of a global route's 19,000 overflow, and its 50 rip-up
# passes made it worse. At 32% the global route has no overflow (8 shared-read
# lines, SF16, 4.7 s).
source $::env(SCRIPTS_DIR)/openroad/common/io.tcl
source $::env(SCRIPTS_DIR)/openroad/common/resizer.tcl

set OVERFLOW 0.25

read_current_odb
set_dont_touch_objects

# Global placement's routability mode sets the routing layers in LibreLane's
# flow; the global router run after CTS (InsertECOBuffers) reads them.
source $::env(SCRIPTS_DIR)/openroad/common/set_routing_layers.tcl

set block [ord::get_db_block]
set die [$block getDieArea]
set mid [expr ([$die yMin] + [$die yMax]) / 2]
set lo -1
set hi -1
foreach inst [$block getInsts] {
    if { ![[$inst getMaster] isBlock] || ![string match "*tile*" [$inst getName]] } { continue }
    set b [$inst getBBox]
    if { [$b yMin] < $mid } {
        if { $lo < 0 || [$b yMax] > $lo } { set lo [$b yMax] }
    } elseif { $hi < 0 || [$b yMin] < $hi } {
        set hi [$b yMin]
    }
}
# The strip's full-width rows (the tiles' halos cut the others short).
set width 0
foreach row [$block getRows] {
    set b [$row getBBox]
    set width [expr max($width, [$b xMax] - [$b xMin])]
}
set saved {}
foreach row [$block getRows] {
    set b [$row getBBox]
    if { [$b yMin] >= $lo && [$b yMax] <= $hi && [$b xMax] - [$b xMin] > $width / 2 } { continue }
    lappend saved [list [$row getName] [$row getSite] {*}[$row getOrigin] [$row getOrient] \
        [$row getDirection] [$row getSiteCount] [$row getSpacing]]
    odb::dbRow_destroy $row
}
set u [$block getDbUnitsPerMicron]
puts "\[INFO\] Placing in the [llength [$block getRows]] rows between y = [expr $lo / double($u)] and [expr $hi / double($u)] um ([llength $saved] rows set aside)."

set arg_list [list]
lappend arg_list -density [expr $::env(PL_TARGET_DENSITY_PCT) / 100.0]
lappend arg_list -overflow $OVERFLOW
set cell_pad_side [expr $::env(GPL_CELL_PADDING) / 2]
lappend arg_list -pad_right $cell_pad_side
lappend arg_list -pad_left $cell_pad_side
lappend arg_list -init_wirelength_coef $::env(PL_WIRE_LENGTH_COEF)
log_cmd global_placement {*}$arg_list

foreach r $saved {
    odb::dbRow_create $block {*}$r
}
puts "\[INFO\] Restored [llength $saved] rows."

unset_dont_touch_objects
source $::env(SCRIPTS_DIR)/openroad/common/set_rc.tcl
estimate_parasitics -placement
write_views
