# One GEMM on the v3 matrix tiles: copy main.c, this Makefile and a launch.h
# (gen_v3.py) into a run directory, then
#   make main.run BSG_MANYCORE_DIR=<bsg_manycore> SF_FMT=sf16|fp16|bf16[_m2]
bsg_tiles_X = 1
bsg_tiles_Y = 1
SF_FMT ?= sf16
export BSG_PLATFORM = verilator
MACH ?= v3
BSG_MACHINE_PATH = $(BSG_MANYCORE_DIR)/machines/$(MACH)_4x2_$(SF_FMT)
export IGNORE_CADENV = 1
MAX_CYCLES = 400000000

all: main.run

OBJECT_FILES = main.o

include $(BSG_MANYCORE_DIR)/software/mk/Makefile.master

main.riscv: $(LINK_SCRIPT) $(OBJECT_FILES) $(SPMD_COMMON_OBJECTS) $(BSG_MANYCORE_LIB) crt.o
	$(RISCV_LINK) $(OBJECT_FILES) $(SPMD_COMMON_OBJECTS) -L. "-l:$(BSG_MANYCORE_LIB)" -o $@ $(RISCV_LINK_OPTS)

main.o: Makefile launch.h

include $(BSG_MANYCORE_DIR)/software/mk/Makefile.tail_rules
