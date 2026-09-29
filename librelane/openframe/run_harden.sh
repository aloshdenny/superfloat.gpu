#!/bin/bash
# Harden the OpenFrame chip (openframe_project_wrapper). Export the tile
# views first (../core_tile/export_views.sh). Run it inside tmux or screen, e.g.
#   tmux new -d -s chip './run_harden.sh config.json harden.log -c OPENROAD_THREADS=11'
# Arguments: [config] [log] [extra librelane options...]. LibreLane is taken
# from $LIBRELANE, else from the librelane checkout next to this repository.
# The log is written next to this script and ends with HARDEN_EXIT <code>.
DIR=$(cd "$(dirname "$0")" && pwd)
LIBRELANE=${LIBRELANE:-$(cd "$DIR/../../../librelane" && pwd)}
CFG=${1:-config.json}
LOG=${2:-harden.log}
shift $(( $# < 2 ? $# : 2 ))
# A tmux server started from another login shell can pass on
# __ETC_PROFILE_NIX_SOURCED, so nix.sh skips PATH setup; load it explicitly.
if ! command -v nix-shell >/dev/null 2>&1; then
  for f in /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh \
           /etc/profile.d/nix.sh "$HOME/.nix-profile/etc/profile.d/nix.sh"; do
    [ -e "$f" ] && { unset __ETC_PROFILE_NIX_SOURCED __ETC_PROFILE_NIX_DAEMON_SOURCED; . "$f"; break; }
  done
fi
cd "$LIBRELANE" || exit 1
nix-shell --run "cd '$DIR' && python3 -m librelane --pdk-root \"\$HOME/.ciel\" $* ./$CFG" 2>&1 | tee "$DIR/$LOG"
echo "HARDEN_EXIT ${PIPESTATUS[0]}" >> "$DIR/$LOG"
