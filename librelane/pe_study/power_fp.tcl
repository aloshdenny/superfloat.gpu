# usage: sta -exit power_fp.tcl  (env: NL TOP SPEF SDC VCD LIB); stimulus tb_power_fp.sv
read_liberty $::env(LIB)
read_verilog $::env(NL)
link_design $::env(TOP)
read_sdc $::env(SDC)
read_spef $::env(SPEF)
set_propagated_clock [all_clocks]
read_vcd -scope tb_power_fp/dut $::env(VCD)
report_power
report_activity_annotation
