# tile.sdc - Signoff constraints for the OpenFrame core tile macro
# Create clock (20.0 ns period = 50.0 MHz)
create_clock -name clk -period 20.0000 [get_ports {clk}]
set_clock_transition 0.3000 [get_clocks {clk}]
set_clock_uncertainty 0.2500 clk
set_propagated_clock [get_clocks {clk}]

# I/O delays (~15% of period; matches IO_DELAY_CONSTRAINT in config.json)
set_input_delay 3.0000 -clock [get_clocks {clk}] [all_inputs]
set_output_delay 3.0000 -clock [get_clocks {clk}] [all_outputs]

# Remove delays from clock port to prevent timing loops
set_input_delay 0.0 -clock [get_clocks {clk}] [get_ports {clk}]

# False path input/output hold checks to prevent artificial buffer insertion
set_false_path -hold -from [all_inputs]
set_false_path -hold -to [all_outputs]

# Chip reset is held for many cycles, so it is left untimed. core_reset is a
# one-cycle pulse from the dispatcher between blocks and stays timed.
set_false_path -from [get_ports {reset}]

set_max_fanout 10 [current_design]
# Sky130 HD cell limit, checked at signoff
set_max_transition 1.5 [current_design]
set_max_capacitance 0.5 [current_design]
