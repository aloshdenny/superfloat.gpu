set ::env(STEP_ID) OpenROAD.IOPlacement
set ::env(TECH_LEF) /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd__max.tlef
set ::env(MACRO_LEFS) ""
set ::env(STD_CELL_LIBRARY) sky130_fd_sc_hd
set ::env(PAD_CELL_LIBRARY) sky130_ef_io
set ::env(VDD_PIN) VPWR
set ::env(GND_PIN) VGND
set ::env(TECH_LEFS) "\"nom_*\" /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd__nom.tlef \"min_*\" /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd__min.tlef \"max_*\" /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd__max.tlef"
set ::env(PRIMARY_GDSII_STREAMOUT_TOOL) magic
set ::env(DEFAULT_CORNER) max_ss_100C_1v60
set ::env(STA_CORNERS) "nom_tt_025C_1v80 nom_ss_100C_1v60 nom_ff_n40C_1v95 min_tt_025C_1v80 min_ss_100C_1v60 min_ff_n40C_1v95 max_tt_025C_1v80 max_ss_100C_1v60 max_ff_n40C_1v95"
set ::env(RT_MIN_LAYER) met1
set ::env(RT_MAX_LAYER) met4
set ::env(SCL_GROUND_PINS) "VGND VNB"
set ::env(SCL_POWER_PINS) "VPWR VPB"
set ::env(TRISTATE_CELLS) "\"sky130_fd_sc_hd__ebuf*\""
set ::env(FILL_CELLS) "sky130_fd_sc_hd__fill_2 sky130_fd_sc_hd__fill_1"
set ::env(DECAP_CELLS) sky130_fd_sc_hd__decap_3
set ::env(CELL_LIBS) "\"*_tt_025C_1v80\" /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib \"*_ff_n40C_1v95\" /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__ff_n40C_1v95.lib \"*_ss_100C_1v60\" /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__ss_100C_1v60.lib"
set ::env(CELL_LEFS) "/Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_sc_hd/lef/sky130_ef_sc_hd.lef /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_sc_hd/lef/sky130_fd_sc_hd.lef"
set ::env(CELL_GDS) /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_sc_hd/gds/sky130_fd_sc_hd.gds
set ::env(CELL_VERILOG_MODELS) /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v
set ::env(CELL_BB_VERILOG_MODELS) "/Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd__blackbox.v /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd__blackbox_pp.v"
set ::env(CELL_SPICE_MODELS) "/Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_sc_hd/spice/sky130_ef_sc_hd__fill_4.spice /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_sc_hd/spice/sky130_ef_sc_hd__decap_60_12.spice /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_sc_hd/spice/sky130_ef_sc_hd__fill_2.spice /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_sc_hd/spice/sky130_fd_sc_hd.spice /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_sc_hd/spice/sky130_ef_sc_hd__decap_40_12.spice /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_sc_hd/spice/sky130_ef_sc_hd__decap_20_12.spice /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_sc_hd/spice/sky130_ef_sc_hd__decap_80_12.spice /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_sc_hd/spice/sky130_ef_sc_hd__fill_8.spice /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_sc_hd/spice/sky130_ef_sc_hd__fill_12.spice /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_sc_hd/spice/sky130_ef_sc_hd__decap_12.spice"
set ::env(CELL_CDLS) /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_sc_hd/cdl/sky130_fd_sc_hd.cdl
set ::env(SYNTH_EXCLUDED_CELL_FILE) /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.tech/librelane/sky130_fd_sc_hd/no_synth.cells
set ::env(PNR_EXCLUDED_CELL_FILE) /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.tech/librelane/sky130_fd_sc_hd/drc_exclude.cells
set ::env(OUTPUT_CAP_LOAD) 33.442
set ::env(MAX_FANOUT_CONSTRAINT) 10
set ::env(MAX_TRANSITION_CONSTRAINT) 1.5
set ::env(MAX_CAPACITANCE_CONSTRAINT) 0.5
set ::env(CLOCK_UNCERTAINTY_CONSTRAINT) 0.25
set ::env(CLOCK_TRANSITION_CONSTRAINT) 0.30
set ::env(TIME_DERATING_CONSTRAINT) 5
set ::env(IO_DELAY_CONSTRAINT) 15
set ::env(SYNTH_DRIVING_CELL) sky130_fd_sc_hd__inv_2/Y
set ::env(SYNTH_TIEHI_CELL) sky130_fd_sc_hd__conb_1/HI
set ::env(SYNTH_TIELO_CELL) sky130_fd_sc_hd__conb_1/LO
set ::env(SYNTH_BUFFER_CELL) sky130_fd_sc_hd__buf_2/A/X
set ::env(PLACE_SITE) unithd
set ::env(CELL_PAD_EXCLUDE) "\"sky130_fd_sc_hd__tap*\" \"sky130_fd_sc_hd__decap*\" \"sky130_ef_sc_hd__decap*\" \"sky130_fd_sc_hd__fill*\""
set ::env(DIODE_CELL) sky130_fd_sc_hd__diode_2/DIODE
set ::env(WELLTAP_CELL) sky130_fd_sc_hd__tapvpwrvgnd_1
set ::env(ENDCAP_CELL) sky130_fd_sc_hd__decap_3
set ::env(DESIGN_NAME) core
set ::env(CLOCK_PERIOD) 24.0
set ::env(CLOCK_PORT) clk
set ::env(DIE_AREA) "0.0 0.0 960.0 500.0"
set ::env(EXTRA_EXCLUDED_CELLS) "sky130_fd_sc_hd__buf_1 sky130_fd_sc_hd__buf_2 sky130_fd_sc_hd__clkbuf_1 sky130_fd_sc_hd__clkdlybuf4s15_1 sky130_fd_sc_hd__clkdlybuf4s15_2 sky130_fd_sc_hd__clkdlybuf4s18_1 sky130_fd_sc_hd__clkdlybuf4s18_2 sky130_fd_sc_hd__clkdlybuf4s25_1 sky130_fd_sc_hd__clkdlybuf4s25_2 sky130_fd_sc_hd__clkdlybuf4s50_1 sky130_fd_sc_hd__clkdlybuf4s50_2 sky130_fd_sc_hd__dlygate4sd1_1 sky130_fd_sc_hd__dlygate4sd2_1 sky130_fd_sc_hd__dlygate4sd3_1 sky130_fd_sc_hd__dlymetal6s2s_1 sky130_fd_sc_hd__dlymetal6s4s_1 sky130_fd_sc_hd__dlymetal6s6s_1"
set ::env(FALLBACK_SDC) /nix/store/98rqv1hffv9cpnxfdv45ccm5ljz7z0xk-python3-3.13.9-env/lib/python3.13/site-packages/librelane/scripts/base.sdc
set ::env(PAD_LIBS) "\"*_tt_025C_1v80\" \"/Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_io/lib/sky130_ef_io__vccd_lvc_clamped_pad_tt_025C_1v80_3v30_3v30.lib /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_io/lib/sky130_ef_io__vssd_lvc_clamped_pad_tt_025C_1v80_3v30.lib /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_io/lib/sky130_ef_io__vddio_hvc_clamped_pad_tt_025C_1v80_3v30_3v30.lib /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_io/lib/sky130_ef_io__vssio_hvc_clamped_pad_tt_025C_1v80_3v30_3v30.lib /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_io/lib/sky130_ef_io__gpiov2_pad_tt_tt_025C_1v80_3v30.lib /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_io/lib/slices_stubs.lib /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_io/lib/sky130_ef_io__analog_stubs.lib\" \"*_ff_n40C_1v95\" \"/Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_io/lib/sky130_ef_io__vccd_lvc_clamped_pad_ff_n40C_1v95_5v50_5v50.lib /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_io/lib/sky130_ef_io__vssd_lvc_clamped_pad_ff_n40C_1v95_5v50.lib /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_io/lib/sky130_ef_io__vddio_hvc_clamped_pad_ff_n40C_1v95_5v50_5v50.lib /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_io/lib/sky130_ef_io__vssio_hvc_clamped_pad_ff_n40C_1v95_5v50_5v50.lib /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_io/lib/sky130_ef_io__gpiov2_pad_ff_ff_n40C_1v95_5v50.lib /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_io/lib/slices_stubs.lib /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_io/lib/sky130_ef_io__analog_stubs.lib\" \"*_ss_100C_1v60\" \"/Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_io/lib/sky130_ef_io__vccd_lvc_clamped_pad_ss_100C_1v60_3v00_3v00.lib /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_io/lib/sky130_ef_io__vssd_lvc_clamped_pad_ss_100C_1v60_3v00.lib /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_io/lib/sky130_ef_io__vddio_hvc_clamped_pad_ss_100C_1v60_3v00_3v00.lib /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_io/lib/sky130_ef_io__vssio_hvc_clamped_pad_ss_100C_1v60_3v00_3v00.lib /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_io/lib/sky130_ef_io__gpiov2_pad_ss_ss_100C_1v60_3v00.lib /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_io/lib/slices_stubs.lib /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_io/lib/sky130_ef_io__analog_stubs.lib\""
set ::env(PAD_LEFS) /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_io/lef/sky130_ef_io.lef
set ::env(PAD_GDS) "/Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_io/gds/sky130_fd_io.gds /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_io/gds/sky130_ef_io.gds /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_io/gds/sky130_ef_io__analog.gds /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_io/gds/sky130_ef_io__connect_vcchib_vccd_and_vswitch_vddio_slice_20um.gds /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_io/gds/sky130_ef_io__connect_vdda_vddio_and_vssa_vssio_slice_20um.gds"
set ::env(PAD_VERILOG_MODELS) "/Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_io/verilog/sky130_fd_io__blackbox_pp.v /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_io/verilog/sky130_ef_io.v"
set ::env(PAD_CDLS) /Users/aoxo/.ciel/ciel/sky130/versions/74c0e6b118a67d94c24172143d3bd597473fa63d/sky130A/libs.ref/sky130_fd_io/cdl/sky130_ef_io.cdl
set ::env(PAD_CORNER) sky130_ef_io__corner_pad
set ::env(PAD_FILLERS) "sky130_ef_io__com_bus_slice_20um sky130_ef_io__com_bus_slice_10um sky130_ef_io__com_bus_slice_5um sky130_ef_io__com_bus_slice_1um"
set ::env(PAD_SITE_NAME) sky130_io
set ::env(PAD_CORNER_SITE_NAME) sky130_io_corner
set ::env(PAD_FAKE_SITES) "sky130_io \"1.0 200\" sky130_io_corner \"200.0 204.0\""
set ::env(PAD_PLACE_IO_TERMINALS) "sky130_ef_io__gpiov2_pad/PAD sky130_ef_io__vccd_lvc_clamped_pad/VCCD_PAD sky130_ef_io__vssd_lvc_clamped_pad/VSSD_PAD sky130_ef_io__vddio_hvc_clamped_pad/VDDIO_PAD sky130_ef_io__vssio_hvc_clamped_pad/VSSIO_PAD sky130_ef_io__analog_esd_pad/P_PAD sky130_ef_io__analog_minesd_pad/P_PAD sky130_ef_io__analog_minesd_pad_short/P_PAD sky130_ef_io__analog_noesd_pad/P_PAD sky130_ef_io__analog_pad/P_PAD"
set ::env(PAD_EDGE_SPACING) 0
set ::env(PAD_ROTATION_HORIZONTAL) R180
set ::env(PAD_ROTATION_VERTICAL) R180
set ::env(PAD_ROTATION_CORNER) R180
set ::env(SET_RC_VERBOSE) 0
set ::env(PDN_CONNECT_MACROS_TO_GRID) 1
set ::env(PDN_ENABLE_GLOBAL_CONNECTIONS) 1
set ::env(PNR_SDC_FILE) /Users/aoxo/vscode/superfloat.gpu/librelane/core/core.sdc
set ::env(DEDUPLICATE_CORNERS) 0
set ::env(IO_PIN_H_LAYER) met3
set ::env(IO_PIN_V_LAYER) met2
set ::env(IO_PIN_V_EXTENSION) 0
set ::env(IO_PIN_H_EXTENSION) 0
set ::env(IO_PIN_V_THICKNESS_MULT) 2
set ::env(IO_PIN_H_THICKNESS_MULT) 2
set ::env(IO_PIN_PLACEMENT_MODE) matching
set ::env(IO_EXCLUDE_PIN_REGION) "\"bottom:*\" left:0-400 right:0-400"
set ::env(CURRENT_ODB) /Users/aoxo/vscode/superfloat.gpu/librelane/core/runs/RUN_2026-07-02_10-20-07/24-openroad-globalplacementskipio/core.odb
set ::env(SAVE_ODB) /Users/aoxo/vscode/superfloat.gpu/librelane/core/runs/RUN_2026-07-02_10-20-07/25-openroad-ioplacement/core.odb
set ::env(SAVE_DEF) /Users/aoxo/vscode/superfloat.gpu/librelane/core/runs/RUN_2026-07-02_10-20-07/25-openroad-ioplacement/core.def
set ::env(SAVE_SDC) /Users/aoxo/vscode/superfloat.gpu/librelane/core/runs/RUN_2026-07-02_10-20-07/25-openroad-ioplacement/core.sdc
set ::env(SAVE_NL) /Users/aoxo/vscode/superfloat.gpu/librelane/core/runs/RUN_2026-07-02_10-20-07/25-openroad-ioplacement/core.nl.v
set ::env(SAVE_PNL) /Users/aoxo/vscode/superfloat.gpu/librelane/core/runs/RUN_2026-07-02_10-20-07/25-openroad-ioplacement/core.pnl.v
