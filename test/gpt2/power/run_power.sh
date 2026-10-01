#!/bin/bash
# Gate-level power of a signed-off OpenFrame chip on one GPT-2 launch.
#
#   run_power.sh <sf16|fp16|bf16> <image dir> [dump start] [dump end]
#
# SYNC=1 runs the sync pin bus. TILE and CHIP name the signed-off runs (their
# final/ views); the defaults are v1's.
# Given a dump window, the run stops at its end; the full launch (no window)
# is also checked against expected.txt.
# The image dir holds prog.hex, data.hex, launch.env and expected.txt
# (image.py). The chip's and its tiles' signoff netlists run on the sky130
# cell models; physical-only cells (fill, decap, tap) are left out of the
# simulation, which they do not affect. The launch's outputs are checked
# against expected.txt. Activity between the dump cycles (default: the whole
# launch) goes to power_sta.sh: OpenSTA's report_power at nom_tt_025C_1v80
# with each block's signoff SPEF, for the chip's top level (the tiles are
# macros there) and for tile 0. Results go to <image dir>/sim/; the dump and
# the simulation build are deleted afterwards unless KEEP_VCD=1. Run it on a
# disk with room: a 10,000-cycle window is about 1.1 GB.
set -euo pipefail
FMT=$1
IMG=$(cd "$2" && pwd)
DS=${3:-0}
DE=${4:-2147483647}
STOP=$([ -n "${4:-}" ] && echo 1 || echo 0)
HERE=$(cd "$(dirname "$0")" && pwd)
LL=${LL:-$HOME/alosh/superfloat.gpu/librelane}
case $FMT in
  sf16) T1=RUN_2026-09-29_00-38-54_eco; C1=chip_20_eco2 ;;
  fp16) T1=fp16_10r_eco5_s; C1=chip_fp16_1_eco_s ;;
  bf16) T1=bf16_4_eco_s; C1=chip_bf16_2_eco4_s ;;
  *) echo "format must be sf16, fp16 or bf16" >&2; exit 1 ;;
esac
TILE=${TILE:-$LL/core_tile/runs/$T1}
CHIP=${CHIP:-$LL/openframe/runs/$C1}
SYNC=${SYNC:-0}
PDK=${PDK:-$HOME/.ciel/ciel/sky130/versions/1689ac3f2dc763876eaf967227c7dfe831b031ae/sky130A}
SC=$PDK/libs.ref/sky130_fd_sc_hd
STA=${STA:-sta}
W=$IMG/sim
mkdir -p "$W"
cd "$W"
cp "$IMG/prog.hex" "$IMG/data.hex" .
# shellcheck disable=SC1091
source "$IMG/launch.env"

strip_physical() {
  grep -v -E '^\s*sky130_fd_sc_hd__(fill|decap|tapvpwrvgnd)_[0-9]+\s+\S+\s*\(\s*\)\s*;\s*$' "$1"
}
strip_physical "$CHIP/final/nl/openframe_project_wrapper.nl.v" > chip.nl.v
strip_physical "$TILE/final/nl/core_tile.nl.v" > tile.nl.v
printf 'module vccd1_connection(); endmodule\nmodule vssd1_connection(); endmodule\n' > stubs.v
TILE0='tb_chip_power.dut.\chip.gpu_inst.tiles[0].tile '
printf '$dumpvars(1, tb_chip_power.dut);\n$dumpvars(0, %s);\n' "$TILE0" > dump_scopes.vh

echo "[run_power] $FMT $KERNEL kc=$KC nb=$NB: compiling"
iverilog -g2012 -DFUNCTIONAL -DUNIT_DELAY=#1 -o sim.vvp -s tb_chip_power -I . \
  -P tb_chip_power.THREADS="$THREADS" -P tb_chip_power.DUMP_START="$DS" -P tb_chip_power.DUMP_END="$DE" -P tb_chip_power.STOP_AT_DUMP_END="$STOP" -P tb_chip_power.SYNC="$SYNC" \
  "$SC/verilog/primitives.v" "$SC/verilog/sky130_fd_sc_hd.v" stubs.v chip.nl.v tile.nl.v "$HERE/tb_chip_power.v"
echo "[run_power] simulating"
/usr/bin/time -v vvp -n sim.vvp > sim.log 2> sim.time || true
grep -E "DONE|STOPPED|TIMEOUT" sim.log
grep -E "Elapsed|Maximum resident" sim.time

[ "$STOP" = 1 ] || python3 - <<'PY'
exp = [tuple(map(int, l.split())) for l in open("../expected.txt") if l.strip()]
mem = [int(l, 16) if l.strip() and "x" not in l.lower() else None for l in open("data_out.hex") if not l.startswith("//")]
bad = [(a, mem[a], w) for a, w in exp if mem[a] != w]
print(f"[run_power] outputs: {len(exp) - len(bad)}/{len(exp)} match" + (f", first bad {bad[:3]}" if bad else ""))
PY

echo "[run_power] power"
TILE=$TILE CHIP=$CHIP "$HERE/power_sta.sh" "$FMT" "$IMG"
# The dump is ~110 KB per cycle; keep it only on request (KEEP_VCD=1).
[ "${KEEP_VCD:-0}" = 1 ] || rm -f power.vcd power_pins.vcd sim.vvp chip.nl.v tile.nl.v
