# The chip core's grid: the platform's (metal1 followpins, metal4 and metal7
# stripes) over its own logic, plus metal8 stripes across the whole core;
# they run over the four tiles (which use metal1-metal7) and connect to each
# tile's metal7 power pins. No halo around the tiles, so the metal7 stripes
# reach into the 6 um channels between them and the core edge.
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^VDD$} -power
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {^VSS$} -ground
global_connect
set_voltage_domain -name {CORE} -power {VDD} -ground {VSS}

define_pdn_grid -name {grid} -voltage_domains {CORE} -pins {metal8}
add_pdn_stripe -grid {grid} -layer {metal1} -width {0.17} -pitch {2.4} -offset {0} -followpins
add_pdn_stripe -grid {grid} -layer {metal4} -width {0.48} -pitch {56.0} -offset {2}
add_pdn_stripe -grid {grid} -layer {metal7} -width {1.40} -pitch {30.0} -offset {2}
add_pdn_stripe -grid {grid} -layer {metal8} -width {1.40} -pitch {30.0} -offset {2}
add_pdn_connect -grid {grid} -layers {metal1 metal4}
add_pdn_connect -grid {grid} -layers {metal4 metal7}
add_pdn_connect -grid {grid} -layers {metal7 metal8}

define_pdn_grid -name {tiles} -voltage_domains {CORE} -macro -default \
  -halo {0.0 0.0 0.0 0.0}
add_pdn_connect -grid {tiles} -layers {metal7 metal8}
