#!/bin/bash
# Harden the OpenFrame core tile. Launch inside screen (tmux is not installed):
#   screen -dmS core_tile_harden ./run_harden.sh [config.json] [log name]
# Writes the log next to this script and appends HARDEN_EXIT <code> at the end.
CFG=${1:-config.json}
LOG=${2:-harden.log}
DIR=/Users/aoxo/vscode/superfloat.gpu/librelane/core_tile
cd /Users/aoxo/vscode/librelane
nix-shell --run "cd $DIR && python3 -m librelane --pdk-root \"\$HOME/.ciel\" ./$CFG" 2>&1 | tee $DIR/$LOG
echo "HARDEN_EXIT ${PIPESTATUS[0]}" >> $DIR/$LOG
