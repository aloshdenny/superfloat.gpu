# The four core tiles in a 2 x 2 grid with a strip between the rows for the
# chip's own logic, as on the SKY130 chip.
set block [ord::get_db_block]
set u [$block getDbUnitsPerMicron]
set tiles {}
foreach inst [$block getInsts] {
    if {[[$inst getMaster] getName] == "core_tile"} { lappend tiles [$inst getName] }
}
set tiles [lsort $tiles]
set m [[$block findInst [lindex $tiles 0]] getMaster]
set w [expr [$m getWidth] / double($u)]
set h [expr [$m getHeight] / double($u)]
set gap $::env(TILE_GAP)
set strip $::env(TILE_STRIP)
set x0 $gap
set x1 [expr $gap * 2 + $w]
set y0 $gap
set y1 [expr $gap + $h + $strip]
set pos [list "$x0 $y0" "$x1 $y0" "$x0 $y1" "$x1 $y1"]
foreach name $tiles p $pos {
    place_macro -macro_name $name -location $p -orientation R0
    puts "placed $name at $p"
}
