# PDN for Tiny Tapeout 8x4 + RAM32 at (10, 10).
# RAM32 VPWR/VGND are met4 stripes at macro-relative X:
#   VPWR: 18.28, 171.88, 325.48
#   VGND: 95.08, 248.68
# Absolute with ram1 @ x=10 → 28.28 / 105.08 / … (pitch 153.6, edge spacing 75.2).
# Do NOT create an OpenROAD macro grid (PDN_CONNECT_MACROS_TO_GRID=false);
# overlapping met4 straps short to the pin ports.

source $::env(SCRIPTS_DIR)/openroad/common/set_global_connections.tcl
set_global_connections

set vert_layer $::env(PDN_VERTICAL_LAYER)

define_pdn_grid \
    -name stdcell_grid \
    -starts_with POWER \
    -voltage_domain CORE \
    -pins $vert_layer

add_pdn_stripe \
    -grid stdcell_grid \
    -layer $vert_layer \
    -width $::env(PDN_VWIDTH) \
    -pitch $::env(PDN_VPITCH) \
    -spacing $::env(PDN_VSPACING) \
    -offset $::env(PDN_VOFFSET) \
    -starts_with POWER

if { $::env(PDN_ENABLE_RAILS) == 1 } {
    add_pdn_stripe \
        -grid stdcell_grid \
        -layer $::env(PDN_RAIL_LAYER) \
        -width $::env(PDN_RAIL_WIDTH) \
        -followpins

    add_pdn_connect \
        -grid stdcell_grid \
        -layers "$::env(PDN_RAIL_LAYER) $vert_layer"
}
