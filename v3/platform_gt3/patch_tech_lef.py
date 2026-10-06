#!/usr/bin/env python3
"""Write the platform's lef/gt3_tech.lef from GT3/techlef/gt3_tech.lef.

  patch_tech_lef.py <GT3/techlef/gt3_tech.lef> <out.lef>

GT3's cells take power only on the buried power rail (BPR), which the
upstream tech LEF declares as a MASTERSLICE layer, and its stack below M0
(VBPR, VSD, VG) has no routing layer to connect. OpenROAD's PDN generator
needs the followpin layer to be a routing layer and one cut layer between
it and M0, so:

  1. BPR becomes a horizontal ROUTING layer, width 0.032, spacing 0.112
     (GT3 DRC BPR.1/BPR.2), pitch 0.144 (one rail per row boundary), as in
     ORFS's gt2n tech LEF.
  2. VSD and VG (contacts inside the cells, no LEF geometry) become
     MASTERSLICE, so VBPR is the only cut between BPR and M0. VBPR then
     models the BPR power tap: in silicon BPR reaches M0 through VBPR,
     SDCON and VSD (GT3 LVS connect sequence); here that stack is one via.
  3. Via4Array's cut rectangle has a typo upstream (y from -0.105, not
     -0.0105; GT2N's rule has -0.0105): fixed.
  4. Power-tap vias for pdn.tcl, with every pad at least the layer's
     minimum area: VBPR_PWR (BPR-M0), V0_PWR..V5_PWR (M0-M6). They are not
     DEFAULT vias, so the router does not use them for signals; VBPR_0 is a
     DEFAULT via so every cut layer has one.

Everything else (M0-RDL widths, pitches, spacings, EOL and corner rules,
the other vias) is upstream's.
"""
import re
import sys

src, out = sys.argv[1], sys.argv[2]
t = open(src).read()


def sub(pat, rep, text, count=1):
    new, n = re.subn(pat, rep, text, count=count, flags=re.S)
    if n != count:
        sys.exit(f"patch_tech_lef: pattern not found: {pat}")
    return new


t = sub(r"LAYER BPR\s+TYPE MASTERSLICE ;\s+END BPR",
        "LAYER BPR\n  TYPE ROUTING ;\n  SPACING 0.112 ;\n  WIDTH 0.032 ;\n  PITCH 0.144 ;\n"
        "  DIRECTION HORIZONTAL ;\n  PROPERTY LEF58_RECTONLY \"RECTONLY ;\" ;\nEND BPR", t)
for lay in ("VSD", "VG"):
    t = sub(rf"LAYER {lay}\s+TYPE CUT ;.*?END {lay}", f"LAYER {lay}\n  TYPE MASTERSLICE ;\nEND {lay}", t)
t = sub(r"(VIARULE Via4Array GENERATE.*?LAYER V4 ;\s+RECT -0\.0105 )-0\.105( 0\.0105 0\.0105 ;)",
        r"\1-0.0105\2", t)

VIAS = """
VIA VBPR_0 DEFAULT
  LAYER VBPR ;
    RECT -0.006 -0.006 0.006 0.006 ;
  LAYER BPR ;
    RECT -0.016 -0.016 0.016 0.016 ;
  LAYER M0 ;
    RECT -0.012 -0.006 0.012 0.006 ;
END VBPR_0

# Power-tap via stack, BPR rail to an M3 stripe (pdn.tcl). Pads meet the
# minimum areas: M0 0.024 x 0.012, M1 0.014 x 0.028, M2 0.024 x 0.012.
VIA VBPR_PWR
  LAYER VBPR ;
    RECT -0.006 -0.006 0.006 0.006 ;
  LAYER BPR ;
    RECT -0.016 -0.016 0.016 0.016 ;
  LAYER M0 ;
    RECT -0.012 -0.006 0.012 0.006 ;
END VBPR_PWR

VIA V0_PWR
  LAYER V0 ;
    RECT -0.007 -0.006 0.007 0.006 ;
  LAYER M0 ;
    RECT -0.012 -0.006 0.012 0.006 ;
  LAYER M1 ;
    RECT -0.007 -0.014 0.007 0.014 ;
END V0_PWR

VIA V1_PWR
  LAYER V1 ;
    RECT -0.007 -0.006 0.007 0.006 ;
  LAYER M1 ;
    RECT -0.007 -0.014 0.007 0.014 ;
  LAYER M2 ;
    RECT -0.012 -0.006 0.012 0.006 ;
END V1_PWR

VIA V2_PWR
  LAYER V2 ;
    RECT -0.007 -0.006 0.007 0.006 ;
  LAYER M2 ;
    RECT -0.012 -0.006 0.012 0.006 ;
  LAYER M3 ;
    RECT -0.007 -0.010 0.007 0.010 ;
END V2_PWR

# M3 stripe to M6 stripe: M4 0.042 x 0.021, M5 0.021 x 0.042 (min areas).
VIA V3_PWR
  LAYER V3 ;
    RECT -0.007 -0.0105 0.007 0.0105 ;
  LAYER M3 ;
    RECT -0.007 -0.0145 0.007 0.0145 ;
  LAYER M4 ;
    RECT -0.021 -0.0105 0.021 0.0105 ;
END V3_PWR

VIA V4_PWR
  LAYER V4 ;
    RECT -0.0105 -0.0105 0.0105 0.0105 ;
  LAYER M4 ;
    RECT -0.021 -0.0105 0.021 0.0105 ;
  LAYER M5 ;
    RECT -0.0105 -0.021 0.0105 0.021 ;
END V4_PWR

VIA V5_PWR
  LAYER V5 ;
    RECT -0.0105 -0.019 0.0105 0.019 ;
  LAYER M5 ;
    RECT -0.0105 -0.025 0.0105 0.025 ;
  LAYER M6 ;
    RECT -0.0165 -0.019 0.0165 0.019 ;
END V5_PWR
"""
t = sub(r"\nVIA V0_0 DEFAULT", VIAS + "\nVIA V0_0 DEFAULT", t)
open(out, "w").write(t)
print(f"wrote {out}")
