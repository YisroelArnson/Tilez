#!/bin/bash
set -euo pipefail
QUILT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$QUILT_ROOT"
mkdir -p .build/module-cache
export CLANG_MODULE_CACHE_PATH="$QUILT_ROOT/.build/module-cache"
swift run --disable-sandbox QuiltCoreChecks
QUILT_BIN="$(swift build --show-bin-path --disable-sandbox)"
swiftc -module-cache-path "$QUILT_ROOT/.build/module-cache" -I "$QUILT_BIN/Modules" \
  "$QUILT_ROOT/Sources/WindowQuilt/Preferences.swift" "$QUILT_ROOT/Tests/PreferencesChecks/main.swift" \
  "$QUILT_BIN/QuiltCore.build/"*.swift.o -o "$QUILT_ROOT/.build/preferences-checks"
"$QUILT_ROOT/.build/preferences-checks"
