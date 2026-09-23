#!/bin/bash
# Pull the latest main, rebuild, and install Tilez into /Applications.
# Also works for a first install. Set TILEZ_INSTALL_DIR to install elsewhere.
set -euo pipefail
TILEZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TILEZ_ROOT"
TILEZ_INSTALLED="${TILEZ_INSTALL_DIR:-/Applications}/Tilez.app"

if [ -n "$(git status --porcelain)" ]; then
  echo "This copy has uncommitted changes. Commit or discard them, then run update again." >&2
  git status --short >&2
  exit 1
fi
before="$(git rev-parse --short HEAD)"
git pull --ff-only
after="$(git rev-parse --short HEAD)"
[ "$before" = "$after" ] && echo "Already up to date at $after; rebuilding anyway." \
  || echo "Updated $before → $after"

bash "$TILEZ_ROOT/scripts/build.sh"

# Quit the running copy so its binary can be replaced.
if pgrep -xq Tilez; then
  osascript -e 'tell application id "com.yisroelarnson.tilez" to quit' || true
  for _ in $(seq 1 50); do pgrep -xq Tilez || break; sleep 0.2; done
  if pgrep -xq Tilez; then echo "Tilez did not quit. Quit it from the menu bar and run update again." >&2; exit 1; fi
fi

rm -rf "$TILEZ_INSTALLED"
ditto "$TILEZ_ROOT/dist/Tilez.app" "$TILEZ_INSTALLED"
open "$TILEZ_INSTALLED"
printf 'Installed and launched: %s\n' "$TILEZ_INSTALLED"
