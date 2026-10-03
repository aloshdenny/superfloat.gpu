# Place-and-route constraints for the OpenFrame chip. Same as chip.sdc (the
# signoff constraints) except tighter repair targets: max transition 1.0 ns
# (signoff 1.5) and max fanout 6 (signoff 10). Chip nets run up to ~1 mm
# along the centre strip and to the pads, where the routed parasitics exceed
# the pre-route estimates, and post-route antenna diodes add up to four loads.

create_clock -name clk -period 20.0000 [get_ports {gpio_in[38]}]
set_clock_transition 0.3000 [get_clocks {clk}]
set_clock_uncertainty 0.2500 clk
set_propagated_clock [get_clocks {clk}]

# Pin bus. In sync mode (openframe_bus.sv) the host samples every bus output
# at the next rising edge and drives IN and ACK for the next one, where they
# are registered at the pins: all are single-cycle paths, with 4 ns of each
# cycle for the pads, the board and the host. The async handshake needs less
# and is covered by the same constraints. START passes through a two-flop
# synchronizer; DONE and core_active are status the host polls.
set bus_inputs  [get_ports {gpio_in[20] gpio_in[21] gpio_in[24] gpio_in[25] gpio_in[26] gpio_in[27] gpio_in[28] gpio_in[29] gpio_in[30] gpio_in[31] gpio_in[32] gpio_in[33] gpio_in[34] gpio_in[35] gpio_in[36] gpio_in[37] gpio_in[39] gpio_in[40]}]
set bus_outputs [get_ports {gpio_out[*]}]
set_input_delay  4.0 -clock [get_clocks {clk}] $bus_inputs
set_output_delay 4.0 -clock [get_clocks {clk}] $bus_outputs
set_false_path -hold -from $bus_inputs
set_false_path -hold -to $bus_outputs

# Reset pads: asynchronous assert, synchronized release inside the design.
set_false_path -from [get_ports {resetb_l porb_l}]

set_max_fanout 6 [current_design]
set_max_transition 1.0 [current_design]
set_max_capacitance 0.5 [current_design]

set_false_path -from [get_ports {gpio_in[21]}]
set_false_path -to [get_ports {gpio_out[22] gpio_out[23] gpio_out[41] gpio_out[42] gpio_out[43]}]

# The pin-bus mode (sync_mode_q, superfloat_openframe.sv) is latched only at
# START, after which the launch sequencer holds the GPU in reset for 4 cycles
# and waits 4 more before the run: no channel makes a request until at least
# 9 cycles after it changes, and it is constant while a kernel runs. Its paths
# (218 loads across the strip) get 4 cycles.
set sync_mode_net [get_nets -quiet chip.bus.sync_mode]
if { [llength $sync_mode_net] } {
    set sync_mode_reg [get_pins -of_objects $sync_mode_net -filter "direction == output"]
    set_multicycle_path 4 -setup -from $sync_mode_reg
    set_multicycle_path 3 -hold  -from $sync_mode_reg
}
