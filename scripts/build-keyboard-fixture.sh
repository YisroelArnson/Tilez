#!/bin/bash
set -euo pipefail
TILEZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TILEZ_ROOT"
export CLANG_MODULE_CACHE_PATH="$TILEZ_ROOT/.build/module-cache"
swift build --disable-sandbox --target Tilez
TILEZ_BIN="$(swift build --show-bin-path --disable-sandbox)"
TILEZ_FIXTURE="$TILEZ_ROOT/.build/Keyboard Fixture.app"
mkdir -p "$TILEZ_FIXTURE/Contents/MacOS"
swiftc -module-cache-path "$CLANG_MODULE_CACHE_PATH" -I "$TILEZ_BIN/Modules" \
    -I "$TILEZ_BIN/TilezSpacesBridge.build" -I Sources/TilezSpacesBridge/include \
    Sources/Tilez/Preferences.swift Sources/Tilez/Accessibility.swift \
    Sources/Tilez/Desktops.swift Sources/Tilez/WindowManager.swift \
    Sources/Tilez/ActiveLayoutManager.swift Sources/Tilez/GridEditorModel.swift \
    Sources/Tilez/GridLauncher.swift Sources/Tilez/GridKeyboard.swift \
    Sources/Tilez/GridOverlayController.swift Sources/Tilez/DesktopGridView.swift Sources/Tilez/GridSearchField.swift \
    Tests/GridKeyboardFixture/main.swift \
    "$TILEZ_BIN/TilezCore.build/"*.swift.o "$TILEZ_BIN/TilezSpacesBridge.build/"*.o \
    -o "$TILEZ_FIXTURE/Contents/MacOS/KeyboardFixture"
cat > "$TILEZ_FIXTURE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.yisroelarnson.tilez.keyboard-fixture</string>
<key>CFBundleName</key><string>Keyboard Fixture</string>
<key>CFBundleExecutable</key><string>KeyboardFixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$TILEZ_FIXTURE"
printf 'Built: %s\n' "$TILEZ_FIXTURE"
