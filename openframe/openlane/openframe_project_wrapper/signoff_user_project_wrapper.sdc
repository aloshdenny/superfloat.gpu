# Clock network
create_clock [get_pins mprj.ahb0_sys.clk_rst_manager.inst_to_wrap/clk] -name clk -period 50
puts "\[INFO\]: Creating clock {clk} for mprj.ahb0_sys.clk_rst_manager.inst_to_wrap/clk with period: 50"

create_clock [get_ports {gpio_in[30]}] -name jtag_clk -period 200

set_clock_groups \
-name clock_group \
-logically_exclusive \
-group [get_clocks {clk}]\
-group [get_clocks {jtag_clk}]

# Clock non-idealities
set_propagated_clock [all_clocks]
set_clock_uncertainty 0.1 [all_clocks]
puts "\[INFO\]: Setting clock uncertainity to: 0.1"

# Maximum transition time for the design nets
set_max_transition 1.5 [current_design]
puts "\[INFO\]: Setting maximum transition to: 1.5"

# Maximum fanout
set_max_fanout 20 [current_design]
puts "\[INFO\]: Setting maximum fanout to: 20"

# Timing paths delays derate
set_timing_derate -early [expr {1-0.05}]
set_timing_derate -late [expr {1+0.05}]
puts "\[INFO\]: Setting timing derate to: [expr {0.05 * 100}] %"

# Reset input delay
set_input_delay [expr $::env(CLOCK_PERIOD) * 0.5] -clock [get_clocks {clk}] [get_ports {resetb_l}]

#------------------------------------------#
# Retrieved Constraints
#------------------------------------------#

# # Clock source latency
# set usr_clk_max_latency 4.57
# set usr_clk_min_latency 4.11
# set clk_max_latency 5.57
# set clk_min_latency 4.65

# set_clock_latency -source -max $clk_max_latency [get_clocks {wb_clk}]
# set_clock_latency -source -min $clk_min_latency [get_clocks {wb_clk}]
# puts "\[INFO\]: Setting clock latency range: $clk_min_latency : $clk_max_latency"

# # Clock input Transition
# set usr_clk_tran 0.13
# set clk_tran 0.61
# set_input_transition $clk_tran [get_ports $clk_input]
# puts "\[INFO\]: Setting clock transition: $clk_tran"

# Input delays
set in_ext_delay 4
puts "\[INFO\]: Setting input ports external delay to: $in_ext_delay"
set_input_delay -max [expr $in_ext_delay + 4.55] -clock [get_clocks {clk}] [get_ports {gpio_in[*]}]
set_input_delay -min [expr $in_ext_delay + 1.26] -clock [get_clocks {clk}] [get_ports {io_in[*]}]

# Input Transition
set_input_transition -max 0.38  [get_ports {gpio_in[*]}]
set_input_transition -min 0.05  [get_ports {gpio_in[*]}]

# Output delays
set out_ext_delay 4
puts "\[INFO\]: Setting output ports external delay to: $out_ext_delay"
set_output_delay -max [expr $out_ext_delay + 9.12] -clock [get_clocks {clk}] [get_ports {gpio_out[*]}]
set_output_delay -max [expr $out_ext_delay + 9.32] -clock [get_clocks {clk}] [get_ports {gpio_oeb[*]}]
set_output_delay -min [expr $out_ext_delay + 3.9]  -clock [get_clocks {clk}] [get_ports {gpio_out[*]}]
set_output_delay -min [expr $out_ext_delay + 2.34] -clock [get_clocks {clk}] [get_ports {gpio_oeb[*]}]

# Output loads
set_load 0.19 [all_outputs]
