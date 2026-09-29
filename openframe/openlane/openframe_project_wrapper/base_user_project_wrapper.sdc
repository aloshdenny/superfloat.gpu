# Clock network
create_clock [get_pins mprj.ahb0_sys.clk_rst_manager.inst_to_wrap/clk] -name clk -period $::env(CLOCK_PERIOD)
puts "\[INFO\]: Creating clock {clk} for mprj.ahb0_sys.clk_rst_manager.inst_to_wrap/clk with period: $::env(CLOCK_PERIOD)"

create_clock [get_ports {gpio_in[30]}] -name jtag_clk -period 200

set_clock_groups \
-name clock_group \
-logically_exclusive \
-group [get_clocks {clk}]\
-group [get_clocks {jtag_clk}]

# Clock non-idealities
set_propagated_clock [all_clocks]
set_clock_uncertainty $::env(SYNTH_CLOCK_UNCERTAINTY) [all_clocks]
puts "\[INFO\]: Setting clock uncertainity to: $::env(SYNTH_CLOCK_UNCERTAINTY)"
set_clock_transition $::env(SYNTH_CLOCK_TRANSITION) [all_clocks]
puts "\[INFO\]: Setting clock transition to: $::env(SYNTH_CLOCK_TRANSITION)"

# Maximum transition time for the design nets
set_max_transition $::env(MAX_TRANSITION_CONSTRAINT) [current_design]
puts "\[INFO\]: Setting maximum transition to: $::env(MAX_TRANSITION_CONSTRAINT)"

# Maximum fanout
set_max_fanout $::env(MAX_FANOUT_CONSTRAINT) [current_design]
puts "\[INFO\]: Setting maximum fanout to: $::env(MAX_FANOUT_CONSTRAINT)"

# Timing paths delays derate
set_timing_derate -early [expr {1-$::env(SYNTH_TIMING_DERATE)}]
set_timing_derate -late [expr {1+$::env(SYNTH_TIMING_DERATE)}]
puts "\[INFO\]: Setting timing derate to: [expr {$::env(SYNTH_TIMING_DERATE) * 100}] %"

# Reset input delay
set_input_delay [expr $::env(CLOCK_PERIOD) * 0.5] -clock [get_clocks {clk}] [get_ports {resetb_l}]

#------------------------------------------#
# Retrieved Constraints
#------------------------------------------#

# Input delays
set in_ext_delay 0
puts "\[INFO\]: Setting input ports external delay to: $in_ext_delay"
set_input_delay -max [expr $in_ext_delay + 4.55] -clock [get_clocks {clk}] [get_ports {gpio_in[*]}]
set_input_delay -min [expr $in_ext_delay + 1.26] -clock [get_clocks {clk}] [get_ports {gpio_in[*]}]

# Input Transition
set_input_transition -max 0.38  [get_ports {gpio_in[*]}]
set_input_transition -min 0.05  [get_ports {gpio_in[*]}]

# Output delays
set out_ext_delay 0
puts "\[INFO\]: Setting output ports external delay to: $out_ext_delay"
set_output_delay -max [expr $out_ext_delay + 9.12] -clock [get_clocks {clk}] [get_ports {gpio_out[*]}]
set_output_delay -max [expr $out_ext_delay + 9.32] -clock [get_clocks {clk}] [get_ports {gpio_oeb[*]}]
set_output_delay -min [expr $out_ext_delay + 2.34] -clock [get_clocks {clk}] [get_ports {gpio_oeb[*]}]
set_output_delay -min [expr $out_ext_delay + 3.9]  -clock [get_clocks {clk}] [get_ports {gpio_out[*]}]

# Output loads
set_load 0.19 [all_outputs]
