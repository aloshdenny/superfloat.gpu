###############################################################################
# Created by write_sdc
###############################################################################
current_design openframe_project_wrapper
###############################################################################
# Timing Constraints
###############################################################################
create_clock -name clk -period 20.0000 [get_ports {gpio_in[38]}]
set_clock_transition 0.3000 [get_clocks {clk}]
set_clock_uncertainty 0.2500 clk
set_propagated_clock [get_clocks {clk}]
set_input_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_in[20]}]
set_input_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_in[21]}]
set_input_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_in[24]}]
set_input_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_in[25]}]
set_input_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_in[26]}]
set_input_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_in[27]}]
set_input_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_in[28]}]
set_input_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_in[29]}]
set_input_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_in[30]}]
set_input_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_in[31]}]
set_input_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_in[32]}]
set_input_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_in[33]}]
set_input_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_in[34]}]
set_input_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_in[35]}]
set_input_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_in[36]}]
set_input_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_in[37]}]
set_input_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_in[39]}]
set_input_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_in[40]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[0]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[10]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[11]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[12]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[13]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[14]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[15]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[16]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[17]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[18]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[19]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[1]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[20]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[21]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[22]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[23]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[24]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[25]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[26]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[27]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[28]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[29]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[2]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[30]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[31]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[32]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[33]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[34]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[35]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[36]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[37]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[38]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[39]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[3]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[40]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[41]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[42]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[43]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[4]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[5]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[6]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[7]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[8]}]
set_output_delay 4.0000 -clock [get_clocks {clk}] -add_delay [get_ports {gpio_out[9]}]
set_multicycle_path -hold\
    -from [list [get_ports {gpio_in[24]}]\
           [get_ports {gpio_in[25]}]\
           [get_ports {gpio_in[26]}]\
           [get_ports {gpio_in[27]}]\
           [get_ports {gpio_in[28]}]\
           [get_ports {gpio_in[29]}]\
           [get_ports {gpio_in[30]}]\
           [get_ports {gpio_in[31]}]\
           [get_ports {gpio_in[32]}]\
           [get_ports {gpio_in[33]}]\
           [get_ports {gpio_in[34]}]\
           [get_ports {gpio_in[35]}]\
           [get_ports {gpio_in[36]}]\
           [get_ports {gpio_in[37]}]\
           [get_ports {gpio_in[39]}]\
           [get_ports {gpio_in[40]}]] 1
set_multicycle_path -hold\
    -to [list [get_ports {gpio_out[0]}]\
           [get_ports {gpio_out[10]}]\
           [get_ports {gpio_out[11]}]\
           [get_ports {gpio_out[12]}]\
           [get_ports {gpio_out[13]}]\
           [get_ports {gpio_out[14]}]\
           [get_ports {gpio_out[15]}]\
           [get_ports {gpio_out[16]}]\
           [get_ports {gpio_out[17]}]\
           [get_ports {gpio_out[18]}]\
           [get_ports {gpio_out[1]}]\
           [get_ports {gpio_out[2]}]\
           [get_ports {gpio_out[3]}]\
           [get_ports {gpio_out[4]}]\
           [get_ports {gpio_out[5]}]\
           [get_ports {gpio_out[6]}]\
           [get_ports {gpio_out[7]}]\
           [get_ports {gpio_out[8]}]\
           [get_ports {gpio_out[9]}]] 1
set_multicycle_path -setup\
    -from [list [get_ports {gpio_in[24]}]\
           [get_ports {gpio_in[25]}]\
           [get_ports {gpio_in[26]}]\
           [get_ports {gpio_in[27]}]\
           [get_ports {gpio_in[28]}]\
           [get_ports {gpio_in[29]}]\
           [get_ports {gpio_in[30]}]\
           [get_ports {gpio_in[31]}]\
           [get_ports {gpio_in[32]}]\
           [get_ports {gpio_in[33]}]\
           [get_ports {gpio_in[34]}]\
           [get_ports {gpio_in[35]}]\
           [get_ports {gpio_in[36]}]\
           [get_ports {gpio_in[37]}]\
           [get_ports {gpio_in[39]}]\
           [get_ports {gpio_in[40]}]] 2
set_multicycle_path -setup\
    -to [list [get_ports {gpio_out[0]}]\
           [get_ports {gpio_out[10]}]\
           [get_ports {gpio_out[11]}]\
           [get_ports {gpio_out[12]}]\
           [get_ports {gpio_out[13]}]\
           [get_ports {gpio_out[14]}]\
           [get_ports {gpio_out[15]}]\
           [get_ports {gpio_out[16]}]\
           [get_ports {gpio_out[17]}]\
           [get_ports {gpio_out[18]}]\
           [get_ports {gpio_out[1]}]\
           [get_ports {gpio_out[2]}]\
           [get_ports {gpio_out[3]}]\
           [get_ports {gpio_out[4]}]\
           [get_ports {gpio_out[5]}]\
           [get_ports {gpio_out[6]}]\
           [get_ports {gpio_out[7]}]\
           [get_ports {gpio_out[8]}]\
           [get_ports {gpio_out[9]}]] 2
set_false_path -hold\
    -from [list [get_ports {gpio_in[20]}]\
           [get_ports {gpio_in[21]}]\
           [get_ports {gpio_in[24]}]\
           [get_ports {gpio_in[25]}]\
           [get_ports {gpio_in[26]}]\
           [get_ports {gpio_in[27]}]\
           [get_ports {gpio_in[28]}]\
           [get_ports {gpio_in[29]}]\
           [get_ports {gpio_in[30]}]\
           [get_ports {gpio_in[31]}]\
           [get_ports {gpio_in[32]}]\
           [get_ports {gpio_in[33]}]\
           [get_ports {gpio_in[34]}]\
           [get_ports {gpio_in[35]}]\
           [get_ports {gpio_in[36]}]\
           [get_ports {gpio_in[37]}]\
           [get_ports {gpio_in[39]}]\
           [get_ports {gpio_in[40]}]]
set_false_path -hold\
    -to [list [get_ports {gpio_out[0]}]\
           [get_ports {gpio_out[10]}]\
           [get_ports {gpio_out[11]}]\
           [get_ports {gpio_out[12]}]\
           [get_ports {gpio_out[13]}]\
           [get_ports {gpio_out[14]}]\
           [get_ports {gpio_out[15]}]\
           [get_ports {gpio_out[16]}]\
           [get_ports {gpio_out[17]}]\
           [get_ports {gpio_out[18]}]\
           [get_ports {gpio_out[19]}]\
           [get_ports {gpio_out[1]}]\
           [get_ports {gpio_out[20]}]\
           [get_ports {gpio_out[21]}]\
           [get_ports {gpio_out[22]}]\
           [get_ports {gpio_out[23]}]\
           [get_ports {gpio_out[24]}]\
           [get_ports {gpio_out[25]}]\
           [get_ports {gpio_out[26]}]\
           [get_ports {gpio_out[27]}]\
           [get_ports {gpio_out[28]}]\
           [get_ports {gpio_out[29]}]\
           [get_ports {gpio_out[2]}]\
           [get_ports {gpio_out[30]}]\
           [get_ports {gpio_out[31]}]\
           [get_ports {gpio_out[32]}]\
           [get_ports {gpio_out[33]}]\
           [get_ports {gpio_out[34]}]\
           [get_ports {gpio_out[35]}]\
           [get_ports {gpio_out[36]}]\
           [get_ports {gpio_out[37]}]\
           [get_ports {gpio_out[38]}]\
           [get_ports {gpio_out[39]}]\
           [get_ports {gpio_out[3]}]\
           [get_ports {gpio_out[40]}]\
           [get_ports {gpio_out[41]}]\
           [get_ports {gpio_out[42]}]\
           [get_ports {gpio_out[43]}]\
           [get_ports {gpio_out[4]}]\
           [get_ports {gpio_out[5]}]\
           [get_ports {gpio_out[6]}]\
           [get_ports {gpio_out[7]}]\
           [get_ports {gpio_out[8]}]\
           [get_ports {gpio_out[9]}]]
set_false_path\
    -from [list [get_ports {gpio_in[20]}]\
           [get_ports {gpio_in[21]}]\
           [get_ports {porb_l}]\
           [get_ports {resetb_l}]]
set_false_path\
    -to [list [get_ports {gpio_out[22]}]\
           [get_ports {gpio_out[23]}]\
           [get_ports {gpio_out[41]}]\
           [get_ports {gpio_out[42]}]\
           [get_ports {gpio_out[43]}]]
###############################################################################
# Environment
###############################################################################
###############################################################################
# Design Rules
###############################################################################
set_max_transition 1.0000 [current_design]
set_max_capacitance 0.5000 [current_design]
set_max_fanout 6.0000 [current_design]
