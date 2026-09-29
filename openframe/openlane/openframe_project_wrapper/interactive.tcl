package require openlane
set script_dir [file dirname [file normalize [info script]]]
set save_path "$script_dir/../.."
prep -design $script_dir -tag $::env(OPENLANE_RUN_TAG) -ignore_mismatches

if { $::env(RUN_LINTER) } {
    run_verilator
}
run_synthesis
run_floorplan
if { ! [ info exists ::env(PLACEMENT_CURRENT_DEF) ] } {
    set ::env(PLACEMENT_CURRENT_DEF) $::env(CURRENT_DEF)
} else {
    set ::env(CURRENT_DEF) $::env(PLACEMENT_CURRENT_DEF)
}
run_placement
if { ! [ info exists ::env(CTS_CURRENT_DEF) ] } {
    set ::env(CTS_CURRENT_DEF) $::env(CURRENT_DEF)
} else {
    set ::env(CURRENT_DEF) $::env(CTS_CURRENT_DEF)
}

run_cts
run_resizer_timing
if { [info exists ::env(FP_DEF_TEMPLATE)] } {
    set log [index_file $::env(floorplan_logs)/custom_apply_def_template.log]
    set def [index_file $::env(floorplan_tmpfiles)/custom_apply_def_template.def]

    puts_info "Custom DEF template step..."
    set var ""
    foreach pin $::env(FP_TEMPLATE_PINS) {set var "--template-pins $pin $var"}
    manipulate_layout $script_dir/CustomApplyDEFTemplate/apply_def_template.py\
        -indexed_log $log\
        -output_def $::env(CURRENT_DEF)\
        --def-template $::env(FP_DEF_TEMPLATE)\
        --input-lef $::env(MERGED_LEF)\
        {*}$var
}
if { ! [ info exists ::env(ROUTING_CURRENT_DEF) ] } {
    set ::env(ROUTING_CURRENT_DEF) $::env(CURRENT_DEF)
} else {
    set ::env(CURRENT_DEF) $::env(ROUTING_CURRENT_DEF)
}
run_routing


if { ! [ info exists ::env(PARSITICS_CURRENT_DEF) ] } {
    set ::env(PARSITICS_CURRENT_DEF) $::env(CURRENT_DEF)
} else {
    set ::env(CURRENT_DEF) $::env(PARSITICS_CURRENT_DEF)
}

if { $::env(RUN_SPEF_EXTRACTION)} {
    run_parasitics_sta
}
if { $::env(RUN_IRDROP_REPORT) } {
    run_irdrop_report
}
if {$::env(RUN_MAGIC)} {
    run_magic
}
if {$::env(RUN_KLAYOUT)} {
    run_klayout
}
if {$::env(RUN_KLAYOUT_XOR)} {
    run_klayout_gds_xor
}
if { ! [ info exists ::env(LVS_CURRENT_DEF) ] } {
    set ::env(LVS_CURRENT_DEF) $::env(CURRENT_DEF)
} else {
    set ::env(CURRENT_DEF) $::env(LVS_CURRENT_DEF)
}

if { $::env(RUN_LVS) } {
    run_magic_spice_export;
    run_lvs; # requires run_magic_spice_export
}
if { ! [ info exists ::env(DRC_CURRENT_DEF) ] } {
    set ::env(DRC_CURRENT_DEF) $::env(CURRENT_DEF)
} else {
    set ::env(CURRENT_DEF) $::env(DRC_CURRENT_DEF)
}
if { $::env(RUN_MAGIC_DRC) } {
    run_magic_drc
}
if {$::env(RUN_KLAYOUT_DRC)} {
    run_klayout_drc
}
if { ! [ info exists ::env(ANTENNA_CHECK_CURRENT_DEF) ] } {
    set ::env(ANTENNA_CHECK_CURRENT_DEF) $::env(CURRENT_DEF)
} else {
    set ::env(CURRENT_DEF) $::env(ANTENNA_CHECK_CURRENT_DEF)
}
run_antenna_check


save_final_views
save_final_views -save_path $save_path -tag $::env(OPENLANE_RUN_TAG)
calc_total_runtime
save_state
generate_final_summary_report
