# KLayout: GT2N's tiehigh/tielow GDS cells under GT3 names (make_tie_cells.py).
#   klayout -b -r tie_gds.py -rd src=<gt2n w31_lvt gds> -rd out=<gt3_tie_gt2n.gds>
import pya
NAMES = {"gt2_6t_tiehigh_w31_lvt": "gt3_6t_tiehi_gt2n", "gt2_6t_tielow_w31_lvt": "gt3_6t_tielo_gt2n"}
ly = pya.Layout(); ly.read(src)
o = pya.Layout(); o.dbu = ly.dbu
for old, new in NAMES.items():
    c = o.create_cell(new)
    c.copy_tree(ly.cell(old))
    print(new, c.dbbox())
o.write(out)
