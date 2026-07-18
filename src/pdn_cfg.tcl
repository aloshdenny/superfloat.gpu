# PDN for Tiny Tapeout 8x4 + RAM32 at (10, 10).
# RAM32 met4 power pin centers (macro-relative): VPWR 19.08 / 172.68 / 326.28, VGND 95.88 / 249.48.
# PDN offset is relative to the CORE edge (LEFT_MARGIN_MULT*0.46 = 2.76 µm), not the die:
#   FP_PDN_VOFFSET = ram_x + 16.32 = 26.32  (matches pin center after left margin).
# Edge spacing 75.2 + width 1.6 → P–G center pitch 76.8; same-net pitch 153.6.
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
