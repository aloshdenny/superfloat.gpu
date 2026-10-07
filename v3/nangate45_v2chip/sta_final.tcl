# Final timing of a routed design on NanGate45: OpenRCX-extracted
# parasitics (6_final.spef, as ORFS's final report), setup and hold,
# overall and register to register, the worst endpoints from and to the
# ports, and the flip-flop count. Times in ns (the platform's unit).
source $::env(SCRIPTS_DIR)/load.tcl
load_design 6_final.odb 6_final.sdc
read_spef $::env(RESULTS_DIR)/6_final.spef
puts "DESIGN $::env(DESIGN_NICKNAME) PERIOD_PS $::env(CLK_PERIOD_PS) TIME_UNIT ns"
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
puts "SETUP_PATHS"
report_checks -path_delay max -format end -group_path_count 5
report_checks -path_delay max -from [all_registers -clock_pins] -to [all_registers -data_pins] -digits 4
puts "HOLD_PATHS"
report_checks -path_delay min -format end -group_path_count 5
puts "FLOPS [llength [all_registers -edge_triggered]]"
report_power -digits 6
