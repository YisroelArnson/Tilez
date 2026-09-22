#!/bin/bash
set -euo pipefail
TILEZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TILEZ_ROOT"
mkdir -p .build/module-cache
export CLANG_MODULE_CACHE_PATH="$TILEZ_ROOT/.build/module-cache"
swift build -c release --disable-sandbox
TILEZ_BIN="$(swift build -c release --show-bin-path --disable-sandbox)"
TILEZ_APP="$TILEZ_ROOT/dist/Tilez.app"
mkdir -p "$TILEZ_APP/Contents/MacOS" "$TILEZ_APP/Contents/Resources"
cp "$TILEZ_BIN/Tilez" "$TILEZ_APP/Contents/MacOS/Tilez"
cat > "$TILEZ_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Tilez</string>
<key>CFBundleDisplayName</key><string>Tilez</string>
<key>CFBundleIdentifier</key><string>com.local.tilez</string>
<key>CFBundleExecutable</key><string>Tilez</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>2.0.0</string>
<key>CFBundleVersion</key><string>10</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSAccessibilityUsageDescription</key><string>Tilez uses Accessibility to arrange the windows you choose and provide snapping and undo.</string>
<key>NSInputMonitoringUsageDescription</key><string>Tilez observes trackpad gestures over title bars for optional swipe snapping.</string>
</dict></plist>
PLIST
if [ -f "$TILEZ_ROOT/Resources/AppIcon.icns" ]; then
  cp "$TILEZ_ROOT/Resources/AppIcon.icns" "$TILEZ_APP/Contents/Resources/"
fi
codesign --force --sign - --identifier com.local.tilez --requirements '=designated => identifier "com.local.tilez"' "$TILEZ_APP"
printf 'Built: %s\n' "$TILEZ_APP"
