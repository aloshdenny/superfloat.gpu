current_design superfloat_openframe
# NanGate45's Liberty is in ns: CLK_PERIOD_PS / 1000.
set clk_period [expr {[info exists ::env(CLK_PERIOD_PS)] ? $::env(CLK_PERIOD_PS) / 1000.0 : 0.65}]
set clk_io_pct 0.2
create_clock -name clk -period $clk_period [get_ports clk]
set non_clock_inputs [all_inputs -no_clocks]
set_input_delay [expr $clk_period * $clk_io_pct] -clock clk $non_clock_inputs
set_output_delay [expr $clk_period * $clk_io_pct] -clock clk [all_outputs]
