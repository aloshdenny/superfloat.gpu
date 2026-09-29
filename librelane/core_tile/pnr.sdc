# Placement and routing constraints. Fanout is held under the signoff
# limit so antenna diodes inserted after the last repair still pass.
# Signoff checks use tile.sdc (max fanout 10).

create_clock -name clk -period 20.0000 [get_ports {clk}]
set_clock_transition 0.3000 [get_clocks {clk}]
set_clock_uncertainty 0.2500 clk
set_propagated_clock [get_clocks {clk}]

set_input_delay 3.0000 -clock [get_clocks {clk}] [all_inputs]
set_output_delay 3.0000 -clock [get_clocks {clk}] [all_outputs]

set_input_delay 0.0 -clock [get_clocks {clk}] [get_ports {clk}]

set_false_path -hold -from [all_inputs]
set_false_path -hold -to [all_outputs]

# Chip reset is held for many cycles, so it is left untimed. core_reset is a
# one-cycle pulse from the dispatcher between blocks and stays timed.
set_false_path -from [get_ports {reset}]

set_max_fanout 8 [current_design]
# below the 1.5 ns cell limit so antenna diodes added after repair still pass
set_max_transition 1.2 [current_design]
set_max_capacitance 0.5 [current_design]
