#!/bin/bash
# Rewrite a hardened tile's LIB views with model.sdc and install them in its
# views directory. Signoff writes the LIB views with tile.sdc, where port
# hold is a false path, so they carry no hold arcs and the chip cannot check
# hold into the tile. Only post-route STA is re-run, on the run's final state.
# Run it inside tmux or screen after export_views.sh, e.g.
#   ./timing_model.sh runs/RUN_... views_fp16 config_fp16.json
# usage: ./timing_model.sh runs/RUN_... [views_dir] [config]
#        (defaults: views, config.json)
set -euo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
RUN=${1%/}
VIEWS=${2:-views}
CFG=${3:-config.json}
TAG=$(basename "$RUN")_model
LAST=$(ls -d "$DIR/$RUN"/[0-9]*-* | sort -V | tail -1)
"$DIR/run_harden.sh" "$CFG" "harden_$TAG.log" --run-tag "$TAG" --overwrite \
    --only OpenROAD.STAPostPNR --with-initial-state "$LAST/state_out.json" \
    -c SIGNOFF_SDC_FILE=dir::model.sdc -c STA_THREADS=2
grep -q "HARDEN_EXIT 0" "$DIR/harden_$TAG.log" || { echo "STA failed: harden_$TAG.log"; exit 1; }
cp -R "$DIR/runs/$TAG/final/lib/." "$DIR/$VIEWS/lib/"
echo "runs/$TAG (model.sdc on $RUN)" > "$DIR/$VIEWS/TIMING_MODEL"
for lib in "$DIR/$VIEWS"/lib/*/*.lib; do
    printf "%-40s %s hold arcs\n" "$(basename "$lib")" "$(grep -c hold_rising "$lib")"
done
