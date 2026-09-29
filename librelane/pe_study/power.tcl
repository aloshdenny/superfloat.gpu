# usage: sta -exit power.tcl  (env: NL SPEF SDC VCD LIB)
read_liberty $::env(LIB)
read_verilog $::env(NL)
link_design systolic_pe
read_sdc $::env(SDC)
read_spef $::env(SPEF)
set_propagated_clock [all_clocks]
read_vcd -scope tb_power/dut $::env(VCD)
report_power
report_activity_annotation
