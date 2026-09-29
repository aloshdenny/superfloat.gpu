#!/bin/bash
# Harden the OpenFrame core tile. Run it inside tmux or screen, e.g.
#   tmux new -d -s tile './run_harden.sh config.json harden.log -c OPENROAD_THREADS=11'
# Arguments: [config] [log] [extra librelane options...]. LibreLane is taken
# from $LIBRELANE, else from the librelane checkout next to this repository.
# The log is written next to this script and ends with HARDEN_EXIT <code>.
DIR=$(cd "$(dirname "$0")" && pwd)
LIBRELANE=${LIBRELANE:-$(cd "$DIR/../../../librelane" && pwd)}
CFG=${1:-config.json}
LOG=${2:-harden.log}
shift $(( $# < 2 ? $# : 2 ))
cd "$LIBRELANE" || exit 1
nix-shell --run "cd '$DIR' && python3 -m librelane --pdk-root \"\$HOME/.ciel\" $* ./$CFG" 2>&1 | tee "$DIR/$LOG"
echo "HARDEN_EXIT ${PIPESTATUS[0]}" >> "$DIR/$LOG"
