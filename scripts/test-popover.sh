#!/bin/bash
set -euo pipefail
QUILT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$QUILT_ROOT"
mkdir -p .build/module-cache
export CLANG_MODULE_CACHE_PATH="$QUILT_ROOT/.build/module-cache"
swift build --disable-sandbox --target QuiltCore
QUILT_BIN="$(swift build --show-bin-path --disable-sandbox)"
swiftc -module-cache-path "$QUILT_ROOT/.build/module-cache" -I "$QUILT_BIN/Modules" \
  Sources/WindowQuilt/MenuPopoverController.swift Tests/MenuPopoverChecks/main.swift \
  "$QUILT_BIN/QuiltCore.build/"*.swift.o -o .build/menu-popover-checks
.build/menu-popover-checks
