#!/usr/bin/env python3
"""GT3 has no tie cells; ORFS needs one tie-high and one tie-low (synthesis
hilomap, floorplan repair_tie_fanout). This takes GT2N's w31 LVT tiehigh /
tielow from ORFS's gt2n platform, whose site (0.042 x 0.144), BPR rails and
M0/M1 rules are GT3's, and writes them under GT3 names:

  lef/gt3_tie_gt2n.lef  the two macros, SITE gt3v1, without GT2N's LVT
                        implant OBS (GT3's tech LEF has no implant layers)
  lib/gt3_tie_gt2n.lib  area, leakage, function, max_capacitance from
                        GT2N's Liberty (no CCS tables), GT3's units
  (gds/gt3_tie_gt2n.gds: tie_gds.py, KLayout)

  make_tie_cells.py <gt2n platform dir> <gt3 platform dir>
"""
import re
import sys

g2, g3 = sys.argv[1], sys.argv[2]
NAMES = {"gt2_6t_tiehigh_w31_lvt": "gt3_6t_tiehi_gt2n", "gt2_6t_tielow_w31_lvt": "gt3_6t_tielo_gt2n"}

lef = open(f"{g2}/lef/gt2_6t_w31_lvt.lef").read()
out = ["VERSION 5.8 ;", 'BUSBITCHARS "[]" ;', 'DIVIDERCHAR "/" ;', ""]
for old, new in NAMES.items():
    m = re.search(rf"MACRO {old}\n.*?END {old}\n", lef, re.S).group(0)
    m = m.replace(old, new).replace("SITE gt2_6t ;", "SITE gt3v1 ;")
    m = re.sub(r"\s*LAYER LVT ;\s*RECT [^;]*;", "", m)
    out.append(m)
out.append("END LIBRARY")
open(f"{g3}/lef/gt3_tie_gt2n.lef", "w").write("\n".join(out) + "\n")

lib = open(f"{g2}/lib/gt2_6t_w31_lvt_tt_0p7v25c.lib").read()
cells = []
for old, new in NAMES.items():
    i = lib.index(f"cell({old})")
    body = lib[i:i + 4000]
    area = re.search(r"area : ([\d.e+-]+)", body).group(1)
    leak = re.search(r"cell_leakage_power : ([\d.e+-]+)", body).group(1)
    func = re.search(r'function : "(\d)"', body).group(1)
    cmax = re.search(r"max_capacitance : ([\d.e+-]+)", body).group(1)
    cells.append(f"""  cell({new}) {{
    /* GT2N {old} */
    area : {area} ;
    cell_leakage_power : {leak} ;
    dont_touch : true ;
    pin(Y) {{
      direction : output ;
      function : "{func}" ;
      max_capacitance : {cmax} ;
    }}
  }}""")
hdr = """/* GT2N tie cells under GT3 names for the ORFS gt3 platform
   (make_tie_cells.py). GT3 ships no tie cells. Units as gt3_rvt_tt_0p7v25c. */
library(gt3_tie_gt2n) {
  delay_model : table_lookup ;
  time_unit : 1ps ;
  voltage_unit : 1V ;
  current_unit : 1mA ;
  capacitive_load_unit(1, pf);
  pulling_resistance_unit : 1ohm ;
  leakage_power_unit : 1uW ;
  nom_process : 1 ;
  nom_temperature : 25 ;
  nom_voltage : 0.7 ;
  operating_conditions(0p7v25c) {
    process : 1 ;
    temperature : 25 ;
    voltage : 0.7 ;
  }
  default_operating_conditions : 0p7v25c ;
"""
open(f"{g3}/lib/gt3_tie_gt2n.lib", "w").write(hdr + "\n".join(cells) + "\n}\n")
print("wrote gt3_tie_gt2n.lef / .lib")
