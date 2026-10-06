#!/bin/bash
# install.sh [GT3 clone] [ORFS flow dir]: build ORFS platforms/gt3 from the
# GT3 PDK (azadnaeemi/GT3 at 65050ce) and this directory's files. GT2N's tie
# cells (make_tie_cells.py) and KLayout layer properties come from the image's
# platforms/gt2n.
set -euo pipefail
G=${1:-/root/GT3}
F=${2:-/OpenROAD-flow-scripts/flow}
H=$(cd "$(dirname "$0")" && pwd)
P=$F/platforms/gt3
[ -d "$G" ] || git clone -q https://github.com/azadnaeemi/GT3 "$G"
(cd "$G" && git checkout -q 65050ce0125f2f25eb1e9a0940e22b7c3bc5eb5c)
mkdir -p $P/lef $P/lib $P/gds
python3 $H/patch_cell_lef.py $G/lef/gt3_std_cell_rvt.lef $G/lib/gt3_rvt_tt_0p7v25c.lib $P/lef/gt3_std_cell_rvt.lef
python3 $H/patch_lib.py $G/lib/gt3_rvt_tt_0p7v25c.lib $P/lib/gt3_rvt_tt_0p7v25c.lib
cp $G/gds/gt3_6t_std_cell_rvt.gds $P/gds/
cp $G/LICENSE $P/LICENSE
python3 $H/patch_tech_lef.py $G/techlef/gt3_tech.lef $P/lef/gt3_tech.lef
python3 $H/make_tie_cells.py $F/platforms/gt2n $P
QT_QPA_PLATFORM=offscreen klayout -b -r $H/tie_gds.py -rd src=$F/platforms/gt2n/gds/gt2_6t_std_cells_w31_lvt.gds -rd out=$P/gds/gt3_tie_gt2n.gds
cp $H/config.mk $H/pdn.tcl $H/tapcell.tcl $H/fastroute.tcl $H/setRC.tcl \
   $H/cells_clkgate.v $H/gt3.lyt $H/itf_to_rc.py $P/
# KLayout layer properties: gt2n's (GT2N and GT3 use the same GDS layer numbers).
cp $F/platforms/gt2n/gt2.lyp $P/gt3.lyp
echo "installed $P"
