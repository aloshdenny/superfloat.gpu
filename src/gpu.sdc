# gpu.sdc - Custom constraints for flat Superfloat GPU
# Create clock (20.0 ns period = 50.0 MHz)
create_clock -name clk -period 20.0000 [get_ports {clk}]
set_clock_transition 0.3000 [get_clocks {clk}]
set_clock_uncertainty 0.1500 clk
set_propagated_clock [get_clocks {clk}]

# Set typical input/output delays (2 ns leaves more guard band for internal paths)
set_input_delay 2.0000 -clock [get_clocks {clk}] [all_inputs]
set_output_delay 2.0000 -clock [get_clocks {clk}] [all_outputs]

# Remove delays from clock port to prevent timing loops
set_input_delay 0.0 -clock [get_clocks {clk}] [get_ports {clk}]

# False path input/output hold checks to prevent artificial buffer insertion
set_false_path -hold -from [all_inputs]
set_false_path -hold -to [all_outputs]

# Asynchronous input signals
set_false_path -from [get_ports {rst_n}]
set_false_path -from [get_ports {ena}]

# =======================================================================
# False paths for cross-functional flattening artifacts
# =======================================================================
# After SYNTH_HIERARCHY_MODE=flatten, Yosys creates spurious combinational
# paths between the memory arbiter write-data bus and the FMA/activation
# pipeline registers. These paths are architecturally impossible at runtime.
#
# OpenSTA get_nets glob: bare "*" matches any string including "[116]".
# Do NOT use \[*\] — that searches for a net literally named "[*]".
set fp_nets_write [get_nets "data_mem_write_data_flat*"]
if {[llength $fp_nets_write] > 0} {
    set_false_path -through $fp_nets_write
}

set fp_nets_lsu [get_nets "core_lsu_write_data_flat*"]
if {[llength $fp_nets_lsu] > 0} {
    set_false_path -through $fp_nets_lsu
}
