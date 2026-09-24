#!/bin/bash
set -euo pipefail
TILEZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TILEZ_ROOT"
export CLANG_MODULE_CACHE_PATH="$TILEZ_ROOT/.build/module-cache"
swift build --disable-sandbox --target Tilez
TILEZ_BIN="$(swift build --show-bin-path --disable-sandbox)"
TILEZ_FIXTURE="$TILEZ_ROOT/.build/Window Menu Fixture.app"
mkdir -p "$TILEZ_FIXTURE/Contents/MacOS"
cat > "$TILEZ_FIXTURE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.yisroelarnson.tilez.menu-fixture</string>
<key>CFBundleName</key><string>Window Menu Fixture</string>
<key>CFBundleExecutable</key><string>WindowMenuFixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
swiftc -module-cache-path "$CLANG_MODULE_CACHE_PATH" -I "$TILEZ_BIN/Modules" \
    -I "$TILEZ_BIN/TilezSpacesBridge.build" -I Sources/TilezSpacesBridge/include \
    Sources/Tilez/Preferences.swift Sources/Tilez/Accessibility.swift \
    Sources/Tilez/Desktops.swift Sources/Tilez/WindowManager.swift \
    Sources/Tilez/ActiveLayoutManager.swift Sources/Tilez/GridEditorModel.swift \
    Sources/Tilez/GridLauncher.swift Sources/Tilez/GridKeyboard.swift Sources/Tilez/Workspaces.swift Sources/Tilez/WorkspaceThumbnail.swift \
    Sources/Tilez/GridOverlayController.swift Sources/Tilez/DesktopGridView.swift Sources/Tilez/GridSearchField.swift \
    Tests/WindowMenuChecks/main.swift \
    "$TILEZ_BIN/TilezCore.build/"*.swift.o "$TILEZ_BIN/TilezSpacesBridge.build/"*.o \
    -o "$TILEZ_FIXTURE/Contents/MacOS/WindowMenuFixture"
codesign --force --sign - "$TILEZ_FIXTURE"
"$TILEZ_FIXTURE/Contents/MacOS/WindowMenuFixture" &
TILEZ_FIXTURE_PID=$!
trap 'kill "$TILEZ_FIXTURE_PID" 2>/dev/null || true' EXIT
sleep 1
"$TILEZ_FIXTURE/Contents/MacOS/WindowMenuFixture" --probe "$TILEZ_FIXTURE_PID"
