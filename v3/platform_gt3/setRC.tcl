# Per-length wire RC for GT3, derived from GT3/nxtgrd/GT3.itf (the StarRC
# interconnect tech file shipped with the PDK) with itf_to_rc.py, which is
# ORFS's platforms/gt2n/itf_to_rc.py unchanged but for its input path:
#
#   R/um  = RPSQ / WMIN
#   C/um  = (Ca + Cb) * 1.5 + 2 * Cc
#     Ca, Cb  parallel plate to the layers above and below (eps * W / d)
#     Cc      sidewall to a min-spaced neighbour (eps * T / SMIN)
#
# This is the same approximation the gt2n platform uses; GT3, like GT2N,
# ships no OpenRCX rules (only ICT/NXTGRD/QRC for proprietary extractors).
# M0-M9 come out identical to GT2N's (same ITF entries); M10/M11 (RPSQ 0.92
# vs 0.42) and M12/M13 (0.1 vs 0.23) differ.
#
# Liberty units (gt3_rvt_tt_0p7v25c.lib): 1 ohm, 1 pF -> ohm/um, pF/um.

set_layer_rc -layer M0  -resistance 621.75 -capacitance 1.200e-04
set_layer_rc -layer M1  -resistance 437.50 -capacitance 1.023e-04
set_layer_rc -layer M2  -resistance 621.75 -capacitance 9.980e-05
set_layer_rc -layer M3  -resistance 437.50 -capacitance 1.023e-04
set_layer_rc -layer M4  -resistance 166.95 -capacitance 1.088e-04
set_layer_rc -layer M5  -resistance 166.95 -capacitance 1.051e-04
set_layer_rc -layer M6  -resistance 26.55  -capacitance 1.119e-04
set_layer_rc -layer M7  -resistance 26.55  -capacitance 1.051e-04
set_layer_rc -layer M8  -resistance 26.55  -capacitance 1.051e-04
set_layer_rc -layer M9  -resistance 26.55  -capacitance 1.051e-04
set_layer_rc -layer M10 -resistance 16.43  -capacitance 1.091e-04
set_layer_rc -layer M11 -resistance 16.43  -capacitance 1.051e-04
set_layer_rc -layer M12 -resistance 0.278  -capacitance 1.205e-04
set_layer_rc -layer M13 -resistance 0.278  -capacitance 1.205e-04
set_layer_rc -layer RDL -resistance 0.006  -capacitance 2.510e-04
# Buried power rail (power only)
set_layer_rc -layer BPR -resistance 24.31  -capacitance 4.054e-04

# Via R per cut, from the ITF RPV values. VBPR here is the platform's
# BPR-to-M0 power-tap via (lef/gt3_tech.lef), which stands for the ITF's
# VBPR (BPR to SDCON, 32.0) and VSD (SDCON to M0, 36.86) in series.
set_layer_rc -via VBPR -resistance 68.86
set_layer_rc -via V0  -resistance 54.99
set_layer_rc -via V1  -resistance 54.99
set_layer_rc -via V2  -resistance 54.99
set_layer_rc -via V3  -resistance 45.78
set_layer_rc -via V4  -resistance 27.80
set_layer_rc -via V5  -resistance 14.89
set_layer_rc -via V6  -resistance 13.26
set_layer_rc -via V7  -resistance 13.26
set_layer_rc -via V8  -resistance 13.26
set_layer_rc -via V9  -resistance 7.65
set_layer_rc -via V10 -resistance 6.08
set_layer_rc -via V11 -resistance 6.08
set_layer_rc -via V12 -resistance 6.08
set_layer_rc -via V13 -resistance 6.08

set_wire_rc -signal -layer M3
set_wire_rc -clock -layer M5
