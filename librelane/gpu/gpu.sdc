# gpu.sdc - Custom constraints for flat Superfloat GPU
# Create clock (24.0 ns period = 41.67 MHz)
create_clock -name clk -period 24.0000 [get_ports {clk}]
set_clock_transition 0.3000 [get_clocks {clk}]
set_clock_uncertainty 0.2500 clk
set_propagated_clock [get_clocks {clk}]

# Set typical input/output delays
set_input_delay 3.0000 -clock [get_clocks {clk}] [all_inputs]
set_output_delay 3.0000 -clock [get_clocks {clk}] [all_outputs]

# Remove delays from clock port to prevent timing loops
set_input_delay 0.0 -clock [get_clocks {clk}] [get_ports {clk}]

# False path input/output hold checks to prevent artificial buffer insertion
set_false_path -hold -from [all_inputs]
set_false_path -hold -to [all_outputs]
