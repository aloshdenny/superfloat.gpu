#!/bin/bash
# Harden the OpenFrame chip (openframe_project_wrapper). Run core_tile/export_views.sh first. Launch inside screen: see librelane/librelane.md.
cd /Users/aoxo/vscode/librelane
nix-shell --run 'cd /Users/aoxo/vscode/superfloat.gpu/librelane/openframe && python3 -m librelane --pdk-root "$HOME/.ciel" ./config.json' 2>&1 | tee /Users/aoxo/vscode/superfloat.gpu/librelane/openframe/harden.log
echo "HARDEN_EXIT ${PIPESTATUS[0]}" >> /Users/aoxo/vscode/superfloat.gpu/librelane/openframe/harden.log
