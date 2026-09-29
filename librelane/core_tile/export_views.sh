#!/bin/bash
# Copy the signed-off core_tile views from a run into core_tile/views/, where
# librelane/openframe/config.json picks them up.
# usage: ./export_views.sh [runs/RUN_...]   (default: newest run)
set -euo pipefail
cd "$(dirname "$0")"
RUN=${1:-runs/$(ls runs | tail -1)}
F=$RUN/final
[ -f "$F/metrics.json" ] || { echo "no final/ in $RUN"; exit 1; }
rm -rf views && mkdir -p views
cp -R "$F"/{gds,lef,nl,pnl,vh,lib,spef,sdf} views/
cp "$F/metrics.json" views/metrics.json
echo "$RUN" > views/SOURCE_RUN
echo "exported $RUN -> views/"
