###############################################################################
# Created by write_sdc
###############################################################################
current_design core_tile
###############################################################################
# Timing Constraints
###############################################################################
create_clock -name clk -period 20.0000 [get_ports {clk}]
set_clock_transition 0.3000 [get_clocks {clk}]
set_clock_uncertainty 0.2500 clk
set_propagated_clock [get_clocks {clk}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {block_id[0]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {block_id[1]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {block_id[2]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {block_id[3]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {block_id[4]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {block_id[5]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {block_id[6]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {block_id[7]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {core_reset}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_data[0]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_data[10]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_data[11]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_data[12]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_data[13]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_data[14]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_data[15]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_data[1]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_data[2]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_data[3]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_data[4]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_data[5]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_data[6]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_data[7]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_data[8]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_data[9]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_ready}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_ready}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {program_mem_read_data[0]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {program_mem_read_data[10]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {program_mem_read_data[11]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {program_mem_read_data[12]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {program_mem_read_data[13]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {program_mem_read_data[14]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {program_mem_read_data[15]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {program_mem_read_data[1]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {program_mem_read_data[2]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {program_mem_read_data[3]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {program_mem_read_data[4]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {program_mem_read_data[5]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {program_mem_read_data[6]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {program_mem_read_data[7]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {program_mem_read_data[8]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {program_mem_read_data[9]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {program_mem_read_ready}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {reset}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {start}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {thread_count[0]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {thread_count[1]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {thread_count[2]}]
set_input_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {thread_count[3]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_address[0]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_address[10]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_address[11]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_address[12]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_address[13]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_address[14]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_address[15]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_address[16]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_address[17]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_address[18]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_address[1]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_address[2]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_address[3]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_address[4]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_address[5]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_address[6]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_address[7]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_address[8]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_address[9]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_read_valid}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_address[0]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_address[10]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_address[11]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_address[12]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_address[13]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_address[14]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_address[15]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_address[16]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_address[17]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_address[18]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_address[1]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_address[2]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_address[3]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_address[4]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_address[5]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_address[6]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_address[7]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_address[8]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_address[9]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_data[0]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_data[10]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_data[11]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_data[12]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_data[13]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_data[14]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_data[15]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_data[1]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_data[2]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_data[3]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_data[4]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_data[5]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_data[6]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_data[7]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_data[8]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_data[9]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {data_mem_write_valid}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {done}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {program_mem_read_address[0]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {program_mem_read_address[1]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {program_mem_read_address[2]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {program_mem_read_address[3]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {program_mem_read_address[4]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {program_mem_read_address[5]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {program_mem_read_address[6]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {program_mem_read_address[7]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {program_mem_read_address[8]}]
set_output_delay 3.0000 -clock [get_clocks {clk}] -add_delay [get_ports {program_mem_read_valid}]
set_false_path -hold\
    -from [list [get_ports {block_id[0]}]\
           [get_ports {block_id[1]}]\
           [get_ports {block_id[2]}]\
           [get_ports {block_id[3]}]\
           [get_ports {block_id[4]}]\
           [get_ports {block_id[5]}]\
           [get_ports {block_id[6]}]\
           [get_ports {block_id[7]}]\
           [get_ports {clk}]\
           [get_ports {core_reset}]\
           [get_ports {data_mem_read_data[0]}]\
           [get_ports {data_mem_read_data[10]}]\
           [get_ports {data_mem_read_data[11]}]\
           [get_ports {data_mem_read_data[12]}]\
           [get_ports {data_mem_read_data[13]}]\
           [get_ports {data_mem_read_data[14]}]\
           [get_ports {data_mem_read_data[15]}]\
           [get_ports {data_mem_read_data[1]}]\
           [get_ports {data_mem_read_data[2]}]\
           [get_ports {data_mem_read_data[3]}]\
           [get_ports {data_mem_read_data[4]}]\
           [get_ports {data_mem_read_data[5]}]\
           [get_ports {data_mem_read_data[6]}]\
           [get_ports {data_mem_read_data[7]}]\
           [get_ports {data_mem_read_data[8]}]\
           [get_ports {data_mem_read_data[9]}]\
           [get_ports {data_mem_read_ready}]\
           [get_ports {data_mem_write_ready}]\
           [get_ports {program_mem_read_data[0]}]\
           [get_ports {program_mem_read_data[10]}]\
           [get_ports {program_mem_read_data[11]}]\
           [get_ports {program_mem_read_data[12]}]\
           [get_ports {program_mem_read_data[13]}]\
           [get_ports {program_mem_read_data[14]}]\
           [get_ports {program_mem_read_data[15]}]\
           [get_ports {program_mem_read_data[1]}]\
           [get_ports {program_mem_read_data[2]}]\
           [get_ports {program_mem_read_data[3]}]\
           [get_ports {program_mem_read_data[4]}]\
           [get_ports {program_mem_read_data[5]}]\
           [get_ports {program_mem_read_data[6]}]\
           [get_ports {program_mem_read_data[7]}]\
           [get_ports {program_mem_read_data[8]}]\
           [get_ports {program_mem_read_data[9]}]\
           [get_ports {program_mem_read_ready}]\
           [get_ports {reset}]\
           [get_ports {start}]\
           [get_ports {thread_count[0]}]\
           [get_ports {thread_count[1]}]\
           [get_ports {thread_count[2]}]\
           [get_ports {thread_count[3]}]]
set_false_path -hold\
    -to [list [get_ports {data_mem_read_address[0]}]\
           [get_ports {data_mem_read_address[10]}]\
           [get_ports {data_mem_read_address[11]}]\
           [get_ports {data_mem_read_address[12]}]\
           [get_ports {data_mem_read_address[13]}]\
           [get_ports {data_mem_read_address[14]}]\
           [get_ports {data_mem_read_address[15]}]\
           [get_ports {data_mem_read_address[16]}]\
           [get_ports {data_mem_read_address[17]}]\
           [get_ports {data_mem_read_address[18]}]\
           [get_ports {data_mem_read_address[1]}]\
           [get_ports {data_mem_read_address[2]}]\
           [get_ports {data_mem_read_address[3]}]\
           [get_ports {data_mem_read_address[4]}]\
           [get_ports {data_mem_read_address[5]}]\
           [get_ports {data_mem_read_address[6]}]\
           [get_ports {data_mem_read_address[7]}]\
           [get_ports {data_mem_read_address[8]}]\
           [get_ports {data_mem_read_address[9]}]\
           [get_ports {data_mem_read_valid}]\
           [get_ports {data_mem_write_address[0]}]\
           [get_ports {data_mem_write_address[10]}]\
           [get_ports {data_mem_write_address[11]}]\
           [get_ports {data_mem_write_address[12]}]\
           [get_ports {data_mem_write_address[13]}]\
           [get_ports {data_mem_write_address[14]}]\
           [get_ports {data_mem_write_address[15]}]\
           [get_ports {data_mem_write_address[16]}]\
           [get_ports {data_mem_write_address[17]}]\
           [get_ports {data_mem_write_address[18]}]\
           [get_ports {data_mem_write_address[1]}]\
           [get_ports {data_mem_write_address[2]}]\
           [get_ports {data_mem_write_address[3]}]\
           [get_ports {data_mem_write_address[4]}]\
           [get_ports {data_mem_write_address[5]}]\
           [get_ports {data_mem_write_address[6]}]\
           [get_ports {data_mem_write_address[7]}]\
           [get_ports {data_mem_write_address[8]}]\
           [get_ports {data_mem_write_address[9]}]\
           [get_ports {data_mem_write_data[0]}]\
           [get_ports {data_mem_write_data[10]}]\
           [get_ports {data_mem_write_data[11]}]\
           [get_ports {data_mem_write_data[12]}]\
           [get_ports {data_mem_write_data[13]}]\
           [get_ports {data_mem_write_data[14]}]\
           [get_ports {data_mem_write_data[15]}]\
           [get_ports {data_mem_write_data[1]}]\
           [get_ports {data_mem_write_data[2]}]\
           [get_ports {data_mem_write_data[3]}]\
           [get_ports {data_mem_write_data[4]}]\
           [get_ports {data_mem_write_data[5]}]\
           [get_ports {data_mem_write_data[6]}]\
           [get_ports {data_mem_write_data[7]}]\
           [get_ports {data_mem_write_data[8]}]\
           [get_ports {data_mem_write_data[9]}]\
           [get_ports {data_mem_write_valid}]\
           [get_ports {done}]\
           [get_ports {program_mem_read_address[0]}]\
           [get_ports {program_mem_read_address[1]}]\
           [get_ports {program_mem_read_address[2]}]\
           [get_ports {program_mem_read_address[3]}]\
           [get_ports {program_mem_read_address[4]}]\
           [get_ports {program_mem_read_address[5]}]\
           [get_ports {program_mem_read_address[6]}]\
           [get_ports {program_mem_read_address[7]}]\
           [get_ports {program_mem_read_address[8]}]\
           [get_ports {program_mem_read_valid}]]
set_false_path\
    -from [get_ports {reset}]
###############################################################################
# Environment
###############################################################################
###############################################################################
# Design Rules
###############################################################################
set_max_transition 1.2000 [current_design]
set_max_capacitance 0.5000 [current_design]
set_max_fanout 8.0000 [current_design]
