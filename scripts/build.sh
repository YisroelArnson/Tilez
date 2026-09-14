#!/bin/bash
set -euo pipefail
QUILT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$QUILT_ROOT"
mkdir -p .build/module-cache
export CLANG_MODULE_CACHE_PATH="$QUILT_ROOT/.build/module-cache"
swift build -c release --disable-sandbox
QUILT_BIN="$(swift build -c release --show-bin-path --disable-sandbox)"
QUILT_APP="$QUILT_ROOT/dist/Window Quilt.app"
mkdir -p "$QUILT_APP/Contents/MacOS" "$QUILT_APP/Contents/Resources"
cp "$QUILT_BIN/WindowQuilt" "$QUILT_APP/Contents/MacOS/WindowQuilt"
cat > "$QUILT_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Window Quilt</string>
<key>CFBundleDisplayName</key><string>Window Quilt</string>
<key>CFBundleIdentifier</key><string>com.local.windowquilt</string>
<key>CFBundleExecutable</key><string>WindowQuilt</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.7.1</string>
<key>CFBundleVersion</key><string>9</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSAccessibilityUsageDescription</key><string>Window Quilt uses Accessibility to arrange the windows you choose and provide snapping and undo.</string>
<key>NSInputMonitoringUsageDescription</key><string>Window Quilt observes trackpad gestures over title bars for optional swipe snapping.</string>
</dict></plist>
PLIST
if [ -f "$QUILT_ROOT/Resources/AppIcon.icns" ]; then
  cp "$QUILT_ROOT/Resources/AppIcon.icns" "$QUILT_APP/Contents/Resources/"
fi
codesign --force --sign - --identifier com.local.windowquilt --requirements '=designated => identifier "com.local.windowquilt"' "$QUILT_APP"
printf 'Built: %s\n' "$QUILT_APP"
