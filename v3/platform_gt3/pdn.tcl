# GT3 power delivery is front-side: the tech LEF has no backside layers, and
# the cells' vdd/vss pins are buried power rails (BPR). Grid:
#   BPR followpins (the rails, 0.032 um)
#   M3 vdd/vss stripe pair over every power-tap column (tapcell.tcl), with
#     a stacked via VBPR-V0-V1-V2 onto each rail of its net
#   M6 horizontal / M7 vertical mesh over the M3 stripes; block pins on M7
# Taps: GT3_TAP_PITCH / GT3_TAP_OFFSET (config.mk), shared with tapcell.tcl.
add_global_connection -net {vdd} -inst_pattern {.*} -pin_pattern {^vdd$} -power
add_global_connection -net {vss} -inst_pattern {.*} -pin_pattern {^vss$} -ground
global_connect

set_voltage_domain -name {CORE} -power {vdd} -ground {vss}

set tp $::env(GT3_TAP_PITCH)
set to $::env(GT3_TAP_OFFSET)
define_pdn_grid -name {grid} -voltage_domains {CORE} -pins {M7}
add_pdn_stripe -grid {grid} -layer {BPR} -width {0.032} -pitch {0.144} -offset {0} -followpins
# Tap column = sites [to, to + 0.084): vdd stripe centred on the first site,
# vss on the second (0.028 wide, 0.014 apart). -offset is to the centreline.
add_pdn_stripe -grid {grid} -layer {M3} -width {0.028} -spacing {0.014} \
  -pitch $tp -offset [expr {$to + 0.021}] -starts_with POWER
add_pdn_stripe -grid {grid} -layer {M6} -width {0.076} -spacing {0.076} \
  -pitch {4.608} -offset {1.152}
add_pdn_stripe -grid {grid} -layer {M7} -width {0.076} -spacing {0.076} \
  -pitch $tp -offset [expr {$to + $tp / 2.0}]
add_pdn_connect -grid {grid} -layers {BPR M3} -fixed_vias {VBPR_PWR V0_PWR V1_PWR V2_PWR}
add_pdn_connect -grid {grid} -layers {M3 M6} -fixed_vias {V3_PWR V4_PWR V5_PWR}
add_pdn_connect -grid {grid} -layers {M6 M7}
