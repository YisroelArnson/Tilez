#!/bin/bash
set -euo pipefail
TILEZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TILEZ_ROOT"
mkdir -p .build/module-cache
export CLANG_MODULE_CACHE_PATH="$TILEZ_ROOT/.build/module-cache"
swift run --disable-sandbox TilezCoreChecks
TILEZ_BIN="$(swift build --show-bin-path --disable-sandbox)"
swiftc -module-cache-path "$TILEZ_ROOT/.build/module-cache" -I "$TILEZ_BIN/Modules" \
  "$TILEZ_ROOT/Sources/Tilez/Preferences.swift" "$TILEZ_ROOT/Tests/PreferencesChecks/main.swift" \
  "$TILEZ_BIN/TilezCore.build/"*.swift.o -o "$TILEZ_ROOT/.build/preferences-checks"
"$TILEZ_ROOT/.build/preferences-checks"
