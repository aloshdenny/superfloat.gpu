# GT3 ships no tap, endcap or well-tie cell. Its cells take power only on
# the buried power rails (BPR); the front-side PDN (pdn.tcl) reaches the
# rails at power-tap columns: two gt3_6t_filler_x1 sites (no M0/M1 shapes)
# at the same x in every row, under the M3 vdd/vss stripe pair, whose
# stacked via (VBPR, V0, V1, V2) lands on every rail it crosses. Aligning
# the columns row to row keeps the via's M1 pad clear of cell pins above
# and below the rail, which a checkerboard (tapcell) would not.
#
# GT3_TAP_PITCH / GT3_TAP_OFFSET (um, from the core's left edge; multiples
# of the 0.042 um site) are shared with pdn.tcl.
cut_rows

set block [ord::get_db_block]
set master [[ord::get_db] findMaster $::env(TAP_CELL_NAME)]
set dbu [$block getDbUnitsPerMicron]
set core [$block getCoreArea]
set site_w [$master getWidth]
set pitch [expr {round($::env(GT3_TAP_PITCH) * $dbu / $site_w) * $site_w}]
set off [expr {round($::env(GT3_TAP_OFFSET) * $dbu / $site_w) * $site_w}]
set x0 [expr {[$core xMin] + $off}]
set n 0
foreach row [$block getRows] {
  set bb [$row getBBox]
  set ry [$bb yMin]
  set orient [$row getOrient]
  for {set x $x0} {$x + 2 * $site_w <= [$bb xMax]} {incr x $pitch} {
    if {$x < [$bb xMin]} { continue }
    foreach i {0 1} {
      set inst [odb::dbInst_create $block $master "PWRTAP_${n}_$i"]
      $inst setOrient $orient
      $inst setLocation [expr {$x + $i * $site_w}] $ry
      $inst setPlacementStatus FIRM
    }
    incr n
  }
}
puts "GT3 power taps: $n two-site taps, column pitch [expr {$pitch / double($dbu)}] um, first at [expr {$off / double($dbu)}] um"
