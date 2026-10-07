# SuperFloat v1 core tile as a bsg_manycore accelerator tile (hb/README.md).
# Included by bsg_manycore/machines/arch_filelist.mk; SF_HB_DIR is the root of
# this repository's hammerblade checkout.
VSOURCES := $(filter-out %/bsg_manycore_hetero_socket.sv,$(VSOURCES))
VSOURCES += $(SF_HB_DIR)/hb/v/bsg_manycore_hetero_socket.sv
VSOURCES += $(SF_HB_DIR)/hb/v/sf_hb_accel.sv
# v3 matrix tile and its PEs (from the gt2n branch's v3/pe, two-stage product and wavefront swap)
VSOURCES += $(SF_HB_DIR)/hb/v3/fp_arith_v3.sv $(SF_HB_DIR)/hb/v3/csa_trees.sv $(SF_HB_DIR)/hb/v3/fpx_align.sv $(SF_HB_DIR)/hb/v3/v3_pe.sv $(SF_HB_DIR)/hb/v3/v3_block.sv
VSOURCES += $(SF_HB_DIR)/hb/v/sf_hb_v3.sv
SF_V1_SOURCES = core_tile.sv core.sv decoder.sv scratchpad.sv controller.sv fetcher.sv \
                scheduler.sv alu.sv fma.sv fp_fma.sv activation.sv fp_activation.sv lsu.sv \
                registers.sv pc.sv systolic_array.sv systolic_pe.sv fp_systolic_array.sv \
                fp_systolic_pe.sv ieee_fma_pe.sv fp_arith.sv branch_diverge.sv cache.sv \
                shared_icache.sv RAM32.v
# v1 modules renamed sf1_* (bsg_manycore has its own alu, lsu, ...): v1_prefix.py
SF_V1_PREFIXED := $(SF_HB_DIR)/hb/build/sf_v1_prefixed.sv
VSOURCES += $(SF_V1_PREFIXED)
$(SF_V1_PREFIXED): $(addprefix $(SF_HB_DIR)/src/,$(SF_V1_SOURCES)) $(SF_HB_DIR)/hb/v1_prefix.py
	mkdir -p $(dir $@)
	python3 $(SF_HB_DIR)/hb/v1_prefix.py $(SF_HB_DIR)/src $@ $(SF_V1_SOURCES)
VSOURCES += $(SF_HB_DIR)/hb/v/sf_nettype_reset.sv
