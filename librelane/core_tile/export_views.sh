#!/bin/bash
# Copy the signed-off core_tile views from a run into core_tile/views/, where
# librelane/openframe/config.json picks them up. The FP16 and BF16 tiles go to
# views_fp16/ and views_bf16/ (openframe/config_fp16.json, config_bf16.json).
# Then run timing_model.sh, so the LIB views carry the hold arcs the chip
# needs.
# usage: ./export_views.sh [runs/RUN_...] [views_dir]
#        (defaults: newest run, views)
set -euo pipefail
cd "$(dirname "$0")"
RUN=${1:-runs/$(ls runs | tail -1)}
DEST=${2:-views}
F=$RUN/final
[ -f "$F/metrics.json" ] || { echo "no final/ in $RUN"; exit 1; }
rm -rf "$DEST" && mkdir -p "$DEST"
cp -R "$F"/{gds,lef,nl,pnl,vh,lib,spef,sdf} "$DEST"/
cp "$F/metrics.json" "$DEST"/metrics.json
echo "$RUN" > "$DEST"/SOURCE_RUN
echo "exported $RUN -> $DEST/"
