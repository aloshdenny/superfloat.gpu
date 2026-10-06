# Final timing of a routed design: as ORFS's final report (no RCX rules on
# GT3, so global-route estimated parasitics), setup and hold, overall,
# register to register, and the hold endpoints that fail.
source $::env(SCRIPTS_DIR)/load.tcl
load_design 6_final.odb 6_final.sdc
estimate_parasitics -global_routing
puts "DESIGN $::env(DESIGN_NICKNAME) PERIOD_PS $::env(CLK_PERIOD_PS)"
report_design_area
puts "SETUP_ALL [sta::worst_slack_cmd max]"
puts "HOLD_ALL [sta::worst_slack_cmd min]"
puts "SETUP_TNS [sta::total_negative_slack_cmd max]"
puts "HOLD_TNS [sta::total_negative_slack_cmd min]"
puts "SETUP_VIOL [sta::endpoint_violation_count max] HOLD_VIOL [sta::endpoint_violation_count min]"
set p [find_timing_paths -path_delay max -from [all_registers -clock_pins] -to [all_registers -data_pins]]
puts "SETUP_R2R [get_property [lindex $p 0] slack]"
set p [find_timing_paths -path_delay min -from [all_registers -clock_pins] -to [all_registers -data_pins]]
puts "HOLD_R2R [get_property [lindex $p 0] slack]"
puts "HOLD_FROM_INPUTS"
report_checks -path_delay min -from [all_inputs] -format end -group_path_count 10
report_checks -path_delay min -to [all_outputs] -format end -group_path_count 3
puts "FLOPS [llength [all_registers]]"
