#!/bin/bash
set -euo pipefail
TILEZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TILEZ_ROOT"
export CLANG_MODULE_CACHE_PATH="$TILEZ_ROOT/.build/module-cache"
swift build --disable-sandbox --target Tilez
TILEZ_BIN="$(swift build --show-bin-path --disable-sandbox)"
swiftc -module-cache-path "$CLANG_MODULE_CACHE_PATH" -I "$TILEZ_BIN/Modules" \
    -I "$TILEZ_BIN/TilezSpacesBridge.build" -I Sources/TilezSpacesBridge/include \
    Sources/Tilez/Preferences.swift Sources/Tilez/Accessibility.swift \
    Sources/Tilez/Desktops.swift Sources/Tilez/WindowManager.swift \
    Sources/Tilez/ActiveLayoutManager.swift Sources/Tilez/GridEditorModel.swift \
    Sources/Tilez/GridLauncher.swift Sources/Tilez/GridKeyboard.swift \
    Sources/Tilez/GridOverlayController.swift Sources/Tilez/DesktopGridView.swift Sources/Tilez/GridSearchField.swift Sources/Tilez/QuickAdd.swift \
    Tests/GridEditorChecks/main.swift \
    "$TILEZ_BIN/TilezCore.build/"*.swift.o "$TILEZ_BIN/TilezSpacesBridge.build/"*.o \
    -o .build/grid-editor-checks
.build/grid-editor-checks "$@"
