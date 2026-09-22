#!/bin/bash
set -euo pipefail
QUILT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$QUILT_ROOT"
export CLANG_MODULE_CACHE_PATH="$QUILT_ROOT/.build/module-cache"
swift build --disable-sandbox --target WindowQuilt
QUILT_BIN="$(swift build --show-bin-path --disable-sandbox)"
QUILT_FIXTURE="$QUILT_ROOT/.build/Window Menu Fixture.app"
mkdir -p "$QUILT_FIXTURE/Contents/MacOS"
cat > "$QUILT_FIXTURE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.local.windowquilt.menu-fixture</string>
<key>CFBundleName</key><string>Window Menu Fixture</string>
<key>CFBundleExecutable</key><string>WindowMenuFixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
swiftc -module-cache-path "$CLANG_MODULE_CACHE_PATH" -I "$QUILT_BIN/Modules" \
    -I "$QUILT_BIN/QuiltSpacesBridge.build" -I Sources/QuiltSpacesBridge/include \
    Sources/WindowQuilt/Preferences.swift Sources/WindowQuilt/Accessibility.swift \
    Sources/WindowQuilt/Desktops.swift Sources/WindowQuilt/WindowManager.swift \
    Sources/WindowQuilt/ActiveLayoutManager.swift Sources/WindowQuilt/GridEditorModel.swift \
    Sources/WindowQuilt/GridLauncher.swift Sources/WindowQuilt/GridKeyboard.swift \
    Sources/WindowQuilt/GridOverlayController.swift Sources/WindowQuilt/DesktopGridView.swift Sources/WindowQuilt/GridSearchField.swift \
    Tests/WindowMenuChecks/main.swift \
    "$QUILT_BIN/QuiltCore.build/"*.swift.o "$QUILT_BIN/QuiltSpacesBridge.build/"*.o \
    -o "$QUILT_FIXTURE/Contents/MacOS/WindowMenuFixture"
codesign --force --sign - "$QUILT_FIXTURE"
"$QUILT_FIXTURE/Contents/MacOS/WindowMenuFixture" &
QUILT_FIXTURE_PID=$!
trap 'kill "$QUILT_FIXTURE_PID" 2>/dev/null || true' EXIT
sleep 1
"$QUILT_FIXTURE/Contents/MacOS/WindowMenuFixture" --probe "$QUILT_FIXTURE_PID"
