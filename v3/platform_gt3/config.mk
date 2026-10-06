# GT3 PDK platform: 3 nm GAAFET (Georgia Tech, azadnaeemi/GT3), front-side
# power delivery onto buried power rails (BPR). Modeled on ORFS's gt2n
# platform (same group, same site and front-side metal stack); differences
# are noted in README.md.
#
# One library: 64 RVT cells, typical corner 0.7 V / 25 C. There is one Vt
# and one nanosheet width, so there is no W/Vt menu as on gt2n.

export PROCESS = 3

#-----------------------------------------------------
# Tech/Libs
#-----------------------------------------------------
# lef/gt3_tech.lef is GT3/techlef/gt3_tech.lef through patch_tech_lef.py
# (BPR as a routing layer, a VBPR power-tap via, the Via4Array fix).
export TECH_LEF = $(PLATFORM_DIR)/lef/gt3_tech.lef
export SC_LEF   = $(PLATFORM_DIR)/lef/gt3_std_cell_rvt.lef

export LIB_FILES = $(PLATFORM_DIR)/lib/gt3_rvt_tt_0p7v25c.lib \
                   $(ADDITIONAL_LIBS)

export GDS_FILES = $(PLATFORM_DIR)/gds/gt3_6t_std_cell_rvt.gds \
                   $(ADDITIONAL_GDS)

# filler: physical only. dffasync_x2/x4: in the LEF, but no Liberty or GDS.
export DONT_USE_CELLS = gt3_6t_filler_x1 \
                        gt3_6t_dffasync_x2_rvt gt3_6t_dffasync_x4_rvt \
                        gt3_6t_tiehi_gt2n gt3_6t_tielo_gt2n

export FILL_CELLS ?= gt3_6t_filler_x1

#-----------------------------------------------------
# Yosys / synthesis
#-----------------------------------------------------
export SYNTH_MINIMUM_KEEP_SIZE ?= 10000

# GT3 has no tie cells. These are GT2N's tiehigh/tielow (w31 lvt) under
# GT3 names, in lef/gt3_tie_gt2n.lef, lib/gt3_tie_gt2n.lib and
# gds/gt3_tie_gt2n.gds (same site and M0/M1 rules): see README.md.
export TIEHI_CELL_AND_PORT = gt3_6t_tiehi_gt2n Y
export TIELO_CELL_AND_PORT = gt3_6t_tielo_gt2n Y
export ADDITIONAL_LEFS += $(PLATFORM_DIR)/lef/gt3_tie_gt2n.lef
export LIB_FILES += $(PLATFORM_DIR)/lib/gt3_tie_gt2n.lib
export GDS_FILES += $(PLATFORM_DIR)/gds/gt3_tie_gt2n.gds

export MIN_BUF_CELL_AND_PORTS = gt3_6t_buf_x1_rvt A Y

# No latch, clock-gate or adder cells in this library.
export LATCH_MAP_FILE   =
export CLKGATE_MAP_FILE = $(PLATFORM_DIR)/cells_clkgate.v
export ADDER_MAP_FILE   =

export ABC_DRIVER_CELL = gt3_6t_buf_x1_rvt
# inv_x1 input cap is 0.505 fF; 4x, as gt2n.
export ABC_LOAD_IN_FF = 2.0

#--------------------------------------------------------
# Floorplan
#--------------------------------------------------------
export PLACE_SITE = gt3v1

export IO_PLACER_H ?= M2
export IO_PLACER_V ?= M3

export PDN_TCL ?= $(PLATFORM_DIR)/pdn.tcl

# Power-tap columns (tapcell.tcl, pdn.tcl): two filler sites every
# GT3_TAP_PITCH um in every row, the first GT3_TAP_OFFSET um from the
# core's left edge. Multiples of the 0.042 um site.
export TAPCELL_TCL ?= $(PLATFORM_DIR)/tapcell.tcl
export TAP_CELL_NAME = gt3_6t_filler_x1
export GT3_TAP_PITCH ?= 4.032
export GT3_TAP_OFFSET ?= 1.008

export RTLMP_MIN_CHANNEL_SIZE ?= 2.0 2.0

#---------------------------------------------------------
# Place
#---------------------------------------------------------
export PLACE_DENSITY ?= 0.40

#---------------------------------------------------------
# Route
#---------------------------------------------------------
# Cell pins are on M1; signals route M2 and up, as on gt2n.
export MIN_ROUTING_LAYER = M2
export MIN_CLK_ROUTING_LAYER = M3
# MAX_ROUTING_LAYER is set per design (designs/gt3/<design>/config.mk), as
# on gt2n: the flow needs it, and each design sets the highest layer it uses.

export FASTROUTE_TCL ?= $(PLATFORM_DIR)/fastroute.tcl

# KLayout technology file (GDS export)
export KLAYOUT_TECH_FILE = $(PLATFORM_DIR)/gt3.lyt

#---------------------------------------------------------
# IR Drop
#---------------------------------------------------------
export PWR_NETS_VOLTAGES ?= vdd 0.7
export GND_NETS_VOLTAGES ?= vss 0.0
export IR_DROP_LAYER ?= BPR
