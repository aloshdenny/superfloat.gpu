# The tile's grid: the platform's (BPR followpins, M3 tap stripes, M6/M7
# mesh), plus M11 stripes above the tile's routing (M2-M10) as its block
# pins, so the chip can reach them from M12 (front-side power: GT2N's tile
# took power on backside BM2 instead).
add_global_connection -net {vdd} -inst_pattern {.*} -pin_pattern {^vdd$} -power
add_global_connection -net {vss} -inst_pattern {.*} -pin_pattern {^vss$} -ground
global_connect
set_voltage_domain -name {CORE} -power {vdd} -ground {vss}

set tp $::env(GT3_TAP_PITCH)
set to $::env(GT3_TAP_OFFSET)
define_pdn_grid -name {grid} -voltage_domains {CORE} -pins {M11}
add_pdn_stripe -grid {grid} -layer {BPR} -width {0.032} -pitch {0.144} -offset {0} -followpins
add_pdn_stripe -grid {grid} -layer {M3} -width {0.028} -spacing {0.014} \
  -pitch $tp -offset [expr {$to + 0.021}] -starts_with POWER
add_pdn_stripe -grid {grid} -layer {M6} -width {0.076} -spacing {0.076} \
  -pitch {4.608} -offset {1.152}
add_pdn_stripe -grid {grid} -layer {M7} -width {0.076} -spacing {0.076} \
  -pitch $tp -offset [expr {$to + $tp / 2.0}]
add_pdn_stripe -grid {grid} -layer {M11} -width {0.224} -spacing {0.224} \
  -pitch [expr {2 * $tp}] -offset [expr {$to + $tp}]
add_pdn_connect -grid {grid} -layers {BPR M3} -fixed_vias {VBPR_PWR V0_PWR V1_PWR V2_PWR}
add_pdn_connect -grid {grid} -layers {M3 M6} -fixed_vias {V3_PWR V4_PWR V5_PWR}
add_pdn_connect -grid {grid} -layers {M6 M7}
add_pdn_connect -grid {grid} -layers {M6 M11}
