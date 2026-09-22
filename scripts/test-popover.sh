#!/bin/bash
set -euo pipefail
TILEZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TILEZ_ROOT"
mkdir -p .build/module-cache
export CLANG_MODULE_CACHE_PATH="$TILEZ_ROOT/.build/module-cache"
swift build --disable-sandbox --target TilezCore
TILEZ_BIN="$(swift build --show-bin-path --disable-sandbox)"
swiftc -module-cache-path "$TILEZ_ROOT/.build/module-cache" -I "$TILEZ_BIN/Modules" \
  Sources/Tilez/MenuPopoverController.swift Tests/MenuPopoverChecks/main.swift \
  "$TILEZ_BIN/TilezCore.build/"*.swift.o -o .build/menu-popover-checks
.build/menu-popover-checks
