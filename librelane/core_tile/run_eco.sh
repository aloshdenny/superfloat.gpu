#!/bin/bash
# Run a tile ECO written by eco_fix.py through tile_flow.py.
#   ./run_eco.sh eco_<run>.json <initial state_out.json> <run tag> [extra librelane options]
DIR=$(cd "$(dirname "$0")" && pwd)
LIBRELANE=${LIBRELANE:-$(cd "$DIR/../../../librelane" && pwd)}
CFG=$1; STATE=$2; TAG=$3; shift 3
if ! command -v nix-shell >/dev/null 2>&1; then
  for f in /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh /etc/profile.d/nix.sh "$HOME/.nix-profile/etc/profile.d/nix.sh"; do
    [ -e "$f" ] && { unset __ETC_PROFILE_NIX_SOURCED __ETC_PROFILE_NIX_DAEMON_SOURCED; . "$f"; break; }; done
fi
cd "$LIBRELANE" || exit 1
nix-shell --run "cd '$DIR' && python3 ./tile_flow.py --pdk-root \"\$HOME/.ciel\" $CFG --with-initial-state $STATE --run-tag $TAG $*" 2>&1 | tee "$DIR/harden_$TAG.log"
echo "HARDEN_EXIT ${PIPESTATUS[0]}" >> "$DIR/harden_$TAG.log"
