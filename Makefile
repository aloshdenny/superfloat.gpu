.PHONY: test compile compile_tb clean

export LIBPYTHON_LOC=$(shell cocotb-config --libpython)
export PYGPI_PYTHON_BIN=$(shell cocotb-config --python-bin)

test_%:
	make compile_tb
	COCOTB_TEST_MODULES=test.test_$* vvp -M $$(cocotb-config --lib-dir) -m $$(cocotb-config --lib-name vpi icarus) build/sim.vvp

compile:
	@mkdir -p build
	sv2v src/*.sv -w build/gpu.v
	echo '`timescale 1ns/1ns' | cat - build/gpu.v > build/temp.v
	mv build/temp.v build/gpu.v

compile_tb:
	@mkdir -p build
	sv2v src/*.sv test/tb_gpu.sv -w build/all.v
	echo '`timescale 1ns/1ns' | cat - build/all.v > build/temp.v
	mv build/temp.v build/all.v
	iverilog -o build/sim.vvp -s tb_gpu -g2012 build/all.v

clean:
	rm -rf build/*.v build/*.vvp test/logs/*.log

# Waveform visualization
show_%: %.vcd %.gtkw
	gtkwave $^
