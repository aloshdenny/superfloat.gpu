# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info
#
# This is the chip-level harness that TinyTapeout's `gl_test` GitHub Action
# runs (`cd test && make clean && GATES=yes make`) against the post-synthesis
# gate-level netlist. It exercises tt_um_aloshdenny_gpu through its real pins
# (test/tb.v + test/test.py), unlike the RTL unit-test suite driven by the
# top-level ../Makefile (which wraps gpu.sv's internals via tb_gpu.sv).

# defaults
SIM ?= icarus
FST ?= -fst # Use more efficient FST format
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../src

# All RTL sources needed for pre-synthesis simulation, in dependency order
# (must match info.yaml's source_files list).
PROJECT_SOURCES = \
	tt_um_aloshdenny_gpu.sv \
	gpu.sv \
	dcr.sv \
	controller.sv \
	dispatch.sv \
	core.sv \
	decoder.sv \
	fetcher.sv \
	scheduler.sv \
	alu.sv \
	fma.sv \
	activation.sv \
	lsu.sv \
	registers.sv \
	pc.sv \
	systolic_array.sv \
	systolic_pe.sv \
	cache.sv \
	branch_diverge.sv

# Sources are SystemVerilog
COMPILE_ARGS += -g2012

ifneq ($(GATES),yes)

# RTL simulation:
SIM_BUILD = sim_build/rtl
VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))

else

# Gate level simulation:
SIM_BUILD = sim_build/gl
COMPILE_ARGS += -DGL_TEST
COMPILE_ARGS += -DFUNCTIONAL
COMPILE_ARGS += -DUSE_POWER_PINS
COMPILE_ARGS += -DSIM
COMPILE_ARGS += -DUNIT_DELAY=\#1
VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/primitives.v
VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v

# this gets copied in by the GDS action workflow
VERILOG_SOURCES += $(PWD)/gate_level_netlist.v

endif

# Allow sharing configuration between design and testbench via `include`:
COMPILE_ARGS += -I$(SRC_DIR)

# Include the testbench sources:
VERILOG_SOURCES += $(PWD)/tb.v
TOPLEVEL = tb

# List test modules to run, separated by commas and without the .py suffix:
COCOTB_TEST_MODULES = test

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim
