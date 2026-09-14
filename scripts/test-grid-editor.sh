#!/bin/bash
set -euo pipefail
QUILT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$QUILT_ROOT"
export CLANG_MODULE_CACHE_PATH="$QUILT_ROOT/.build/module-cache"
swift build --disable-sandbox --target WindowQuilt
QUILT_BIN="$(swift build --show-bin-path --disable-sandbox)"
swiftc -module-cache-path "$CLANG_MODULE_CACHE_PATH" -I "$QUILT_BIN/Modules" \
    -I "$QUILT_BIN/QuiltSpacesBridge.build" -I Sources/QuiltSpacesBridge/include \
    Sources/WindowQuilt/Preferences.swift Sources/WindowQuilt/Accessibility.swift \
    Sources/WindowQuilt/Desktops.swift Sources/WindowQuilt/WindowManager.swift \
    Sources/WindowQuilt/ActiveLayoutManager.swift Sources/WindowQuilt/GridEditorModel.swift \
    Sources/WindowQuilt/GridLauncher.swift Tests/GridEditorChecks/main.swift \
    "$QUILT_BIN/QuiltCore.build/"*.swift.o "$QUILT_BIN/QuiltSpacesBridge.build/"*.o \
    -o .build/grid-editor-checks
.build/grid-editor-checks
