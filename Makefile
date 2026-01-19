.PHONY: test compile compile_tb clean test_all waves

export LIBPYTHON_LOC=$(shell cocotb-config --libpython)
export PYGPI_PYTHON_BIN=$(shell cocotb-config --python-bin)

# =============================================================================
# Original GPU testbench targets
# =============================================================================

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

# =============================================================================
# Unit Test Targets for Individual Modules
# =============================================================================

# FMA Unit
compile_fma:
	@mkdir -p build build/waves
	sv2v src/fma.sv test/tb_fma.sv -w build/fma.v
	echo '`timescale 1ns/1ns' | cat - build/fma.v > build/temp.v
	mv build/temp.v build/fma.v
	iverilog -o build/fma.vvp -s tb_fma -g2012 build/fma.v

test_fma_unit: compile_fma
	@mkdir -p test/results build/waves
	COCOTB_TEST_MODULES=test.test_fma_unit vvp -M $$(cocotb-config --lib-dir) -m $$(cocotb-config --lib-name vpi icarus) build/fma.vvp

# ALU Unit
compile_alu:
	@mkdir -p build build/waves
	sv2v src/alu.sv test/tb_alu.sv -w build/alu.v
	echo '`timescale 1ns/1ns' | cat - build/alu.v > build/temp.v
	mv build/temp.v build/alu.v
	iverilog -o build/alu.vvp -s tb_alu -g2012 build/alu.v

test_alu_unit: compile_alu
	@mkdir -p test/results build/waves
	COCOTB_TEST_MODULES=test.test_alu_unit vvp -M $$(cocotb-config --lib-dir) -m $$(cocotb-config --lib-name vpi icarus) build/alu.vvp

# Activation Unit
compile_activation:
	@mkdir -p build build/waves
	sv2v src/activation.sv test/tb_activation.sv -w build/activation.v
	echo '`timescale 1ns/1ns' | cat - build/activation.v > build/temp.v
	mv build/temp.v build/activation.v
	iverilog -o build/activation.vvp -s tb_activation -g2012 build/activation.v

test_activation_unit: compile_activation
	@mkdir -p test/results build/waves
	COCOTB_TEST_MODULES=test.test_activation_unit vvp -M $$(cocotb-config --lib-dir) -m $$(cocotb-config --lib-name vpi icarus) build/activation.vvp

# Systolic PE Unit
compile_systolic_pe:
	@mkdir -p build build/waves
	sv2v src/systolic_pe.sv test/tb_systolic_pe.sv -w build/systolic_pe.v
	echo '`timescale 1ns/1ns' | cat - build/systolic_pe.v > build/temp.v
	mv build/temp.v build/systolic_pe.v
	iverilog -o build/systolic_pe.vvp -s tb_systolic_pe -g2012 build/systolic_pe.v

test_systolic_pe_unit: compile_systolic_pe
	@mkdir -p test/results build/waves
	COCOTB_TEST_MODULES=test.test_systolic_pe_unit vvp -M $$(cocotb-config --lib-dir) -m $$(cocotb-config --lib-name vpi icarus) build/systolic_pe.vvp

# Systolic Array Unit
compile_systolic_array:
	@mkdir -p build build/waves
	sv2v src/systolic_pe.sv src/systolic_array.sv test/tb_systolic_array.sv -w build/systolic_array.v
	echo '`timescale 1ns/1ns' | cat - build/systolic_array.v > build/temp.v
	mv build/temp.v build/systolic_array.v
	iverilog -o build/systolic_array.vvp -s tb_systolic_array -g2012 build/systolic_array.v

test_systolic_array_unit: compile_systolic_array
	@mkdir -p test/results build/waves
	COCOTB_TEST_MODULES=test.test_systolic_array_unit vvp -M $$(cocotb-config --lib-dir) -m $$(cocotb-config --lib-name vpi icarus) build/systolic_array.vvp

# Cache Unit
compile_cache:
	@mkdir -p build build/waves
	sv2v src/cache.sv test/tb_cache.sv -w build/cache.v
	echo '`timescale 1ns/1ns' | cat - build/cache.v > build/temp.v
	mv build/temp.v build/cache.v
	iverilog -o build/cache.vvp -s tb_cache -g2012 build/cache.v

test_cache_unit: compile_cache
	@mkdir -p test/results build/waves
	COCOTB_TEST_MODULES=test.test_cache_unit vvp -M $$(cocotb-config --lib-dir) -m $$(cocotb-config --lib-name vpi icarus) build/cache.vvp

# Decoder Unit
compile_decoder:
	@mkdir -p build build/waves
	sv2v src/decoder.sv test/tb_decoder.sv -w build/decoder.v
	echo '`timescale 1ns/1ns' | cat - build/decoder.v > build/temp.v
	mv build/temp.v build/decoder.v
	iverilog -o build/decoder.vvp -s tb_decoder -g2012 build/decoder.v

test_decoder_unit: compile_decoder
	@mkdir -p test/results build/waves
	COCOTB_TEST_MODULES=test.test_decoder_unit vvp -M $$(cocotb-config --lib-dir) -m $$(cocotb-config --lib-name vpi icarus) build/decoder.vvp

# LSU Unit
compile_lsu:
	@mkdir -p build build/waves
	sv2v src/lsu.sv test/tb_lsu.sv -w build/lsu.v
	echo '`timescale 1ns/1ns' | cat - build/lsu.v > build/temp.v
	mv build/temp.v build/lsu.v
	iverilog -o build/lsu.vvp -s tb_lsu -g2012 build/lsu.v

test_lsu_unit: compile_lsu
	@mkdir -p test/results build/waves
	COCOTB_TEST_MODULES=test.test_lsu_unit vvp -M $$(cocotb-config --lib-dir) -m $$(cocotb-config --lib-name vpi icarus) build/lsu.vvp

# =============================================================================
# Run All Unit Tests
# =============================================================================

test_all_units: test_fma_unit test_alu_unit test_activation_unit test_systolic_pe_unit test_systolic_array_unit test_cache_unit test_decoder_unit test_lsu_unit
	@echo "All unit tests completed"

# =============================================================================
# Cleanup
# =============================================================================

clean:
	rm -rf build/*.v build/*.vvp test/logs/*.log test/results/*.log build/waves/*.vcd

clean_waves:
	rm -rf build/waves/*.vcd

# =============================================================================
# Waveform Visualization
# =============================================================================

# View waveforms with GTKWave
waves_fma:
	gtkwave build/waves/fma.vcd test/gtkwave/fma.gtkw &

waves_alu:
	gtkwave build/waves/alu.vcd test/gtkwave/alu.gtkw &

waves_activation:
	gtkwave build/waves/activation.vcd test/gtkwave/activation.gtkw &

waves_systolic_pe:
	gtkwave build/waves/systolic_pe.vcd test/gtkwave/systolic_pe.gtkw &

waves_systolic_array:
	gtkwave build/waves/systolic_array.vcd test/gtkwave/systolic_array.gtkw &

waves_cache:
	gtkwave build/waves/cache.vcd test/gtkwave/cache.gtkw &

waves_decoder:
	gtkwave build/waves/decoder.vcd test/gtkwave/decoder.gtkw &

waves_lsu:
	gtkwave build/waves/lsu.vcd test/gtkwave/lsu.gtkw &

# Generic waveform viewer
show_%: build/waves/%.vcd
	@# Prefer loading the saved GTKWave layout if it exists (auto-adds signals).
	@( \
		if [ -f test/gtkwave/$*.gtkw ]; then \
			gtkwave $< test/gtkwave/$*.gtkw; \
		else \
			gtkwave $<; \
		fi \
	) &

# =============================================================================
# Test Reports
# =============================================================================

report:
	@python -m test.helpers.report

# =============================================================================
# Help
# =============================================================================

help:
	@echo "Atreides GPU Test Suite"
	@echo ""
	@echo "Unit Tests:"
	@echo "  make test_fma_unit          - Test FMA (Q1.15 fused multiply-add)"
	@echo "  make test_alu_unit          - Test ALU (integer operations)"
	@echo "  make test_activation_unit   - Test Activation unit"
	@echo "  make test_systolic_pe_unit  - Test Systolic PE"
	@echo "  make test_systolic_array_unit - Test Systolic Array"
	@echo "  make test_cache_unit        - Test Instruction Cache"
	@echo "  make test_decoder_unit      - Test Instruction Decoder"
	@echo "  make test_lsu_unit          - Test Load-Store Unit"
	@echo "  make test_all_units         - Run all unit tests"
	@echo ""
	@echo "Integration Tests:"
	@echo "  make test_matmul            - Matrix multiplication test"
	@echo "  make test_matadd            - Matrix addition test"
	@echo ""
	@echo "Waveforms:"
	@echo "  make waves_<module>         - View waveforms (fma, alu, etc.)"
	@echo ""
	@echo "Reports:"
	@echo "  make report                 - Generate test summary reports"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean                  - Remove generated files"
	@echo "  make clean_waves            - Remove only waveform files"
