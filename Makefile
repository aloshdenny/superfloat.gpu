.PHONY: test compile compile_tb clean test_all waves openlane_all

export LIBPYTHON_LOC=$(shell cocotb-config --libpython)
export PYGPI_PYTHON_BIN=$(shell cocotb-config --python-bin)

# =============================================================================
# Configuration
# =============================================================================

# OpenLane path (set to your OpenLane installation)
OPENLANE_ROOT ?= $(HOME)/OpenLane
PDK_ROOT ?= $(HOME)/.ciel
PDK ?= sky130A
OPENLANE_IMAGE ?= ghcr.io/the-openroad-project/openlane:latest

# KLayout executable path (macOS)
KLAYOUT := /Applications/KLayout/klayout.app/Contents/MacOS/klayout
KLAYOUT_LYP := scripts/sky130.lyp

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

# Systolic Array Cluster (8 arrays of 8x8 PEs)
compile_systolic_cluster:
	@mkdir -p build build/waves
	sv2v src/systolic_pe.sv src/systolic_array.sv src/systolic_array_cluster.sv test/tb_systolic_array_cluster.sv -w build/systolic_cluster.v
	echo '`timescale 1ns/1ns' | cat - build/systolic_cluster.v > build/temp.v
	mv build/temp.v build/systolic_cluster.v
	iverilog -o build/systolic_cluster.vvp -s tb_systolic_array_cluster -g2012 build/systolic_cluster.v

test_systolic_cluster_unit: compile_systolic_cluster
	@mkdir -p test/results build/waves
	@echo "Running systolic cluster test (8 arrays of 8x8 PEs)..."
	vvp build/systolic_cluster.vvp

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
# Physical Layout Generation (KLayout)
# =============================================================================

# KLayout executable path (macOS)
KLAYOUT := /Applications/KLayout/klayout.app/Contents/MacOS/klayout
KLAYOUT_LYP := scripts/sky130.lyp

layout:
	@echo "Generating physical layout images from GDS..."
	$(KLAYOUT) -b -r scripts/generate_layout.py

view_layout:
	@echo "Opening GDS in KLayout with Sky130 layer colors..."
	$(KLAYOUT) -l $(KLAYOUT_LYP) gds/atreides.gds &

# Generate zoom sequence for video
zoom_sequence:
	@echo "Generating zoom sequence frames (this may take a few minutes)..."
	$(KLAYOUT) -b -r scripts/generate_zoom_sequence.py

# Create zoom-out video from frames (requires ffmpeg)
zoom_video: zoom_sequence
	@echo "Creating zoom-out video..."
	@mkdir -p build
	ffmpeg -y -framerate 30 -i build/zoom_sequence/frame_%04d.png \
		-c:v libx264 -pix_fmt yuv420p -crf 18 -preset slow \
		build/gpu_zoomout.mp4
	@echo "Video created: build/gpu_zoomout.mp4"

# Create smooth 60fps video with motion interpolation
zoom_video_smooth: zoom_sequence
	@echo "Creating smooth 60fps zoom-out video..."
	@mkdir -p build
	ffmpeg -y -framerate 30 -i build/zoom_sequence/frame_%04d.png \
		-filter:v "minterpolate=fps=60:mi_mode=mci:mc_mode=aobmc:vsbmc=1" \
		-c:v libx264 -pix_fmt yuv420p -crf 18 -preset slow \
		build/gpu_zoomout_smooth.mp4
	@echo "Video created: build/gpu_zoomout_smooth.mp4"

# Create high-quality 4K video
zoom_video_4k: zoom_sequence
	@echo "Creating 4K zoom-out video..."
	@mkdir -p build
	ffmpeg -y -framerate 24 -i build/zoom_sequence/frame_%04d.png \
		-c:v libx264 -pix_fmt yuv420p -crf 15 -preset veryslow \
		-tune film build/gpu_zoomout_4k.mp4
	@echo "Video created: build/gpu_zoomout_4k.mp4"

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
	@echo "Atreides GPU Test Suite & Build System"
	@echo ""
	@echo "Architecture: 4 cores, 4 threads/block, 8x8 systolic arrays (8 per core)"
	@echo ""
	@echo "Unit Tests:"
	@echo "  make test_fma_unit            - Test FMA (Q1.15 fused multiply-add)"
	@echo "  make test_alu_unit            - Test ALU (integer operations)"
	@echo "  make test_activation_unit     - Test Activation unit"
	@echo "  make test_systolic_pe_unit    - Test Systolic PE"
	@echo "  make test_systolic_array_unit - Test 8x8 Systolic Array"
	@echo "  make test_systolic_cluster_unit - Test Systolic Array Cluster (8 arrays)"
	@echo "  make test_cache_unit          - Test Instruction Cache"
	@echo "  make test_decoder_unit        - Test Instruction Decoder"
	@echo "  make test_lsu_unit            - Test Load-Store Unit"
	@echo "  make test_all_units           - Run all unit tests"
	@echo ""
	@echo "Integration Tests:"
	@echo "  make test_matmul              - Matrix multiplication test"
	@echo "  make test_matadd              - Matrix addition test"
	@echo ""
	@echo "Compilation:"
	@echo "  make compile                  - Compile GPU to Verilog (sv2v)"
	@echo "  make compile_tb               - Compile with testbench"
	@echo "  make compile_openlane         - Prepare all modules for OpenLane"
	@echo ""
	@echo "OpenLane GDSII Generation:"
	@echo "  make setup_openlane_design    - Setup design in ~/OpenLane/designs/atreides"
	@echo "  make openlane_docker          - Run OpenLane via Docker (RECOMMENDED)"
	@echo ""
	@echo "OpenLane Hierarchical Build (Advanced):"
	@echo "  make openlane_pe              - Build systolic PE macro"
	@echo "  make openlane_systolic_array  - Build 8x8 systolic array macro"
	@echo "  make openlane_systolic_cluster - Build systolic cluster (8 arrays)"
	@echo "  make openlane_core            - Build compute core macro"
	@echo "  make openlane_gpu             - Build full GPU (uses core macros)"
	@echo "  make openlane_all             - Build complete hierarchy (bottom-up)"
	@echo ""
	@echo "Waveforms:"
	@echo "  make waves_<module>           - View waveforms (fma, alu, etc.)"
	@echo "  make waves_systolic_cluster   - View systolic cluster waveforms"
	@echo ""
	@echo "Physical Layout:"
	@echo "  make layout                   - Generate physical layout images (KLayout)"
	@echo "  make view_layout              - Open GDS in KLayout GUI"
	@echo "  make zoom_video               - Create zoom-out video"
	@echo ""
	@echo "Reports:"
	@echo "  make report                   - Generate test summary reports"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean                    - Remove generated files"
	@echo "  make clean_openlane           - Remove OpenLane runs"

# =============================================================================
# OpenLane GDSII Generation (Hierarchical Build)
# =============================================================================

# OpenLane designs directory
OPENLANE_DESIGNS := $(OPENLANE_ROOT)/designs

# Prepare Verilog files for OpenLane (local openlane/ directory)
compile_openlane:
	@echo "Preparing Verilog files for OpenLane..."
	@mkdir -p openlane/pe/src openlane/systolic_array/src openlane/systolic_cluster/src openlane/core/src openlane/gpu/src
	sv2v src/systolic_pe.sv -w openlane/pe/src/systolic_pe.v
	sv2v src/systolic_pe.sv src/systolic_array.sv -w openlane/systolic_array/src/systolic_array.v
	sv2v src/systolic_pe.sv src/systolic_array.sv src/systolic_array_cluster.sv -w openlane/systolic_cluster/src/systolic_array_cluster.v
	sv2v src/*.sv -w openlane/core/src/core.v
	sv2v src/*.sv -w openlane/gpu/src/gpu.v
	@echo "Done! Verilog files ready in openlane/*/src/"

# Setup design in ~/OpenLane/designs/ for Docker-based flow
setup_openlane_design: compile_openlane
	@echo "Setting up Atreides design in $(OPENLANE_DESIGNS)..."
	@mkdir -p $(OPENLANE_DESIGNS)/atreides/src
	@echo "Copying Verilog files..."
	cp openlane/gpu/src/gpu.v $(OPENLANE_DESIGNS)/atreides/src/
	@echo "Adding newline to end of file (POSIX compliance)..."
	@echo "" >> $(OPENLANE_DESIGNS)/atreides/src/gpu.v
	@echo "Creating config.json..."
	@echo '{\n\
    "DESIGN_NAME": "gpu",\n\
    "VERILOG_FILES": "dir::src/gpu.v",\n\
    "CLOCK_PORT": "clk",\n\
    "CLOCK_PERIOD": 40.0,\n\
    "FP_SIZING": "absolute",\n\
    "DIE_AREA": "0 0 4000 4000",\n\
    "FP_CORE_UTIL": 25,\n\
    "PL_TARGET_DENSITY": 0.30,\n\
    "GRT_ADJUSTMENT": 0.15,\n\
    "GRT_OVERFLOW_ITERS": 100,\n\
    "GRT_ALLOW_CONGESTION": true,\n\
    "DRT_THREADS": 2,\n\
    "ROUTING_CORES": 2,\n\
    "RUN_LINTER": false,\n\
    "RUN_CVC": false,\n\
    "GRT_REPAIR_ANTENNAS": true,\n\
    "DIODE_ON_PORTS": "in",\n\
    "RUN_HEURISTIC_DIODE_INSERTION": true,\n\
    "FP_PDN_CHECK_NODES": false,\n\
    "RUN_KLAYOUT_XOR": false,\n\
    "RUN_KLAYOUT_DRC": false,\n\
    "MAX_FANOUT_CONSTRAINT": 8,\n\
    "SYNTH_STRATEGY": "DELAY 0",\n\
    "PL_RESIZER_DESIGN_OPTIMIZATIONS": true,\n\
    "PL_RESIZER_TIMING_OPTIMIZATIONS": true,\n\
    "GLB_RESIZER_TIMING_OPTIMIZATIONS": true,\n\
    "pdk::sky130*": {\n\
        "CLOCK_PERIOD": 40.0,\n\
        "scl::sky130_fd_sc_hd": {\n\
            "CLOCK_PERIOD": 40.0\n\
        }\n\
    }\n\
}' > $(OPENLANE_DESIGNS)/atreides/config.json
	@echo ""
	@echo "=========================================="
	@echo "Design setup complete!"
	@echo "=========================================="
	@echo "Location: $(OPENLANE_DESIGNS)/atreides/"
	@echo ""
	@echo "Directory structure:"
	@echo "  atreides/"
	@echo "  ├── config.json"
	@echo "  └── src/"
	@echo "      └── gpu.v"
	@echo ""
	@echo "To run OpenLane (Docker):"
	@echo "  cd ~/OpenLane"
	@echo "  make mount"
	@echo "  ./flow.tcl -design atreides"
	@echo ""

# Run OpenLane via Docker (flat build - simpler, no hierarchy)
openlane_docker: setup_openlane_design
	@echo "Running OpenLane Docker flow for Atreides..."
	@echo "Using image: $(OPENLANE_IMAGE)"
	@echo "PDK Root: $(PDK_ROOT)"
	cd $(OPENLANE_ROOT) && \
		docker run --rm \
		-v $(OPENLANE_ROOT):/openlane \
		-v $(PDK_ROOT):/.ciel \
		-e PDK_ROOT=/.ciel \
		-e PDK=$(PDK) \
		-e PWD=/openlane \
		-w /openlane \
		$(OPENLANE_IMAGE) \
		./flow.tcl -design atreides -tag atreides_run -overwrite
	@echo "Build complete! Copying GDS..."
	@mkdir -p gds
	cp $(OPENLANE_DESIGNS)/atreides/runs/atreides_run/results/final/gds/gpu.gds gds/atreides_v2.gds
	@echo "Final GDS: gds/atreides_v2.gds"

# Build systolic PE (leaf macro) - for hierarchical flow
openlane_pe: compile_openlane
	@echo "Building systolic PE macro..."
	cd $(OPENLANE_ROOT) && \
		./flow.tcl -design $(CURDIR)/openlane/pe \
		-tag pe_run \
		-overwrite
	@echo "PE macro built! GDS at openlane/pe/runs/pe_run/results/final/gds/"

# Build 8x8 systolic array (uses PE macros)
openlane_systolic_array: openlane_pe
	@echo "Building 8x8 systolic array macro..."
	cd $(OPENLANE_ROOT) && \
		./flow.tcl -design $(CURDIR)/openlane/systolic_array \
		-tag systolic_array_run \
		-overwrite
	@echo "Systolic array macro built!"

# Build systolic cluster (8 arrays)
openlane_systolic_cluster: openlane_systolic_array
	@echo "Building systolic cluster macro (8 arrays)..."
	cd $(OPENLANE_ROOT) && \
		./flow.tcl -design $(CURDIR)/openlane/systolic_cluster \
		-tag systolic_cluster_run \
		-overwrite
	@echo "Systolic cluster macro built!"

# Build compute core (uses systolic cluster macro)
openlane_core: openlane_systolic_cluster
	@echo "Building compute core macro..."
	cd $(OPENLANE_ROOT) && \
		./flow.tcl -design $(CURDIR)/openlane/core \
		-tag core_run \
		-overwrite
	@echo "Core macro built!"

# Build full GPU (uses core macros)
openlane_gpu: openlane_core
	@echo "Building full GPU (4 cores)..."
	cd $(OPENLANE_ROOT) && \
		./flow.tcl -design $(CURDIR)/openlane/gpu \
		-tag gpu_run \
		-overwrite
	@echo "GPU GDSII complete!"
	@echo "Final GDS: openlane/gpu/runs/gpu_run/results/final/gds/gpu.gds"
	@mkdir -p gds
	cp openlane/gpu/runs/gpu_run/results/final/gds/gpu.gds gds/atreides_v2.gds
	@echo "Copied to gds/atreides_v2.gds"

# Build complete hierarchy (bottom-up)
openlane_all: openlane_gpu
	@echo ""
	@echo "=============================================="
	@echo "HIERARCHICAL BUILD COMPLETE!"
	@echo "=============================================="
	@echo ""
	@echo "Build hierarchy:"
	@echo "  └── GPU (4 cores)"
	@echo "      └── Core (4 threads + systolic cluster)"
	@echo "          └── Systolic Cluster (8 arrays)"
	@echo "              └── Systolic Array (8x8 PEs)"
	@echo "                  └── Systolic PE (MAC unit)"
	@echo ""
	@echo "Final GDS: gds/atreides_v2.gds"

# Clean OpenLane runs
clean_openlane:
	rm -rf openlane/*/runs
	rm -rf openlane/*/src/*.v

# View systolic cluster waveforms
waves_systolic_cluster:
	gtkwave build/waves/systolic_cluster.vcd &
