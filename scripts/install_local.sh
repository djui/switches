#!/usr/bin/env bash
# Builds a Release app, replaces /Applications/Switches.app and restarts it.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build_release.sh

if pgrep -x Switches >/dev/null; then
  osascript -e 'quit app "Switches"' >/dev/null 2>&1 || true
  for _ in {1..50}; do
    pgrep -x Switches >/dev/null || break
    sleep 0.1
  done
  pkill -x Switches 2>/dev/null || true
fi

rm -rf /Applications/Switches.app
ditto build/Switches.app /Applications/Switches.app
open /Applications/Switches.app
echo "Installed /Applications/Switches.app"
