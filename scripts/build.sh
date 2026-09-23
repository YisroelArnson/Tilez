#!/bin/bash
# Build dist/Tilez.app. The version is TILEZ_VERSION, else the latest v* tag; the build number
# is the commit count, so it always increases. TILEZ_RELEASE=1 (set by scripts/release.sh)
# adds the Sparkle update feed; builds from source update with scripts/update.sh instead.
set -euo pipefail
TILEZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TILEZ_ROOT"
mkdir -p .build/module-cache
export CLANG_MODULE_CACHE_PATH="$TILEZ_ROOT/.build/module-cache"
TILEZ_VERSION="${TILEZ_VERSION:-$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null | sed 's/^v//' || true)}"
TILEZ_VERSION="${TILEZ_VERSION:-2.0.0}"
TILEZ_BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
SPARKLE_FEED="https://github.com/YisroelArnson/Tilez/releases/latest/download/appcast.xml"
SPARKLE_PUBLIC_KEY="6J1ID7e48qeOnQd3il4ZHsa804XQxgsl0LEK5yaTaNY="
swift build -c release --disable-sandbox
TILEZ_BIN="$(swift build -c release --show-bin-path --disable-sandbox)"
TILEZ_APP="$TILEZ_ROOT/dist/Tilez.app"
mkdir -p "$TILEZ_APP/Contents/MacOS" "$TILEZ_APP/Contents/Resources"
cp "$TILEZ_BIN/Tilez" "$TILEZ_APP/Contents/MacOS/Tilez"
# SwiftPM leaves Sparkle beside the binary; an app bundle loads it from Contents/Frameworks.
install_name_tool -add_rpath "@executable_path/../Frameworks" "$TILEZ_APP/Contents/MacOS/Tilez"
rm -rf "$TILEZ_APP/Contents/Frameworks"
mkdir -p "$TILEZ_APP/Contents/Frameworks"
ditto "$TILEZ_BIN/Sparkle.framework" "$TILEZ_APP/Contents/Frameworks/Sparkle.framework"
UPDATES=""
if [ "${TILEZ_RELEASE:-0}" = 1 ]; then
  UPDATES="<key>SUFeedURL</key><string>$SPARKLE_FEED</string>
<key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_KEY</string>
<key>SUEnableAutomaticChecks</key><true/>"
fi
cat > "$TILEZ_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Tilez</string>
<key>CFBundleDisplayName</key><string>Tilez</string>
<key>CFBundleIdentifier</key><string>com.yisroelarnson.tilez</string>
<key>CFBundleExecutable</key><string>Tilez</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$TILEZ_VERSION</string>
<key>CFBundleVersion</key><string>$TILEZ_BUILD</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSAccessibilityUsageDescription</key><string>Tilez uses Accessibility to arrange the windows you choose and provide snapping and undo.</string>
<key>NSInputMonitoringUsageDescription</key><string>Tilez observes trackpad gestures over title bars for optional swipe snapping.</string>
$UPDATES
</dict></plist>
PLIST
if [ -f "$TILEZ_ROOT/Resources/AppIcon.icns" ]; then
  cp "$TILEZ_ROOT/Resources/AppIcon.icns" "$TILEZ_APP/Contents/Resources/"
fi
codesign --force --sign - --identifier com.yisroelarnson.tilez --requirements '=designated => identifier "com.yisroelarnson.tilez"' "$TILEZ_APP"
printf 'Built: %s (%s, build %s)\n' "$TILEZ_APP" "$TILEZ_VERSION" "$TILEZ_BUILD"
