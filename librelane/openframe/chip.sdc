# Chip-level constraints for openframe_project_wrapper (Atreides SF16, 4 core tiles).
# The clock enters on gpio[38] (Caravel board oscillator pin).

create_clock -name clk -period 20.0000 [get_ports {gpio_in[38]}]
set_clock_transition 0.3000 [get_clocks {clk}]
set_clock_uncertainty 0.2500 clk
set_propagated_clock [get_clocks {clk}]

# Pin bus. bus_ack and start pass through two-flop synchronizers; bus_in is
# sampled only after the synchronized ACK, and the thread count only after the
# synchronized START, so those inputs are not single-cycle paths. They keep a
# 4 ns budget so the input buffering stays short.
set bus_inputs  [get_ports {gpio_in[20] gpio_in[21] gpio_in[24] gpio_in[25] gpio_in[26] gpio_in[27] gpio_in[28] gpio_in[29] gpio_in[30] gpio_in[31] gpio_in[32] gpio_in[33] gpio_in[34] gpio_in[35] gpio_in[36] gpio_in[37] gpio_in[39] gpio_in[40]}]
set bus_outputs [get_ports {gpio_out[*]}]
set_input_delay  4.0 -clock [get_clocks {clk}] $bus_inputs
set_output_delay 4.0 -clock [get_clocks {clk}] $bus_outputs
set_false_path -hold -from $bus_inputs
set_false_path -hold -to $bus_outputs

# Reset pads: asynchronous assert, synchronized release inside the design.
set_false_path -from [get_ports {resetb_l porb_l}]

set_max_fanout 10 [current_design]
set_max_transition 1.5 [current_design]
set_max_capacitance 0.5 [current_design]
