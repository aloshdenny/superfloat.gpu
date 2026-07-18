# LibreLane-compatible PDN config for Tiny Tapeout + RAM32.
# Kept as reference; src/config.json currently uses the LibreLane default
# PDN (no PDN_CFG) with PDN_VPITCH=153.6 / PDN_VOFFSET=26.32 for RAM32 align.
#
# If re-enabled via "PDN_CFG": "dir::pdn_cfg.tcl", use PDN_* env names
# (LibreLane 3); the old FP_PDN_* names are not always exported to TCL.

source $::env(SCRIPTS_DIR)/openroad/common/set_global_connections.tcl
set_global_connections

set vert_layer $::env(PDN_VERTICAL_LAYER)
set vwidth $::env(PDN_VWIDTH)
set vpitch $::env(PDN_VPITCH)
set voffset $::env(PDN_VOFFSET)

define_pdn_grid \
    -name stdcell_grid \
    -starts_with POWER \
    -voltage_domain CORE \
    -pins $vert_layer

add_pdn_stripe \
    -grid stdcell_grid \
    -layer $vert_layer \
    -width $vwidth \
    -pitch $vpitch \
    -offset $voffset \
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
