#!/bin/bash
set -euo pipefail
TILEZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TILEZ_ROOT"
mkdir -p .build/module-cache
export CLANG_MODULE_CACHE_PATH="$TILEZ_ROOT/.build/module-cache"
swift build --target TilezCore --disable-sandbox
TILEZ_BIN="$(swift build --show-bin-path --disable-sandbox)"
TILEZ_FIXTURE="$TILEZ_ROOT/.build/Tilez Popover Check.app"
mkdir -p "$TILEZ_FIXTURE/Contents/MacOS" /private/tmp/tilez-popover-check
rm -f /private/tmp/tilez-popover-check/native-regression.json
swiftc -module-cache-path "$TILEZ_ROOT/.build/module-cache" -I "$TILEZ_BIN/Modules" \
  "$TILEZ_ROOT/Sources/Tilez/MenuPopoverController.swift" "$TILEZ_ROOT/Tests/PopoverFixture/main.swift" \
  "$TILEZ_BIN/TilezCore.build/"*.swift.o -o "$TILEZ_FIXTURE/Contents/MacOS/TilezPopoverCheck"
cat > "$TILEZ_FIXTURE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Tilez Popover Check</string>
<key>CFBundleIdentifier</key><string>com.yisroelarnson.tilez.popovercheck</string>
<key>CFBundleExecutable</key><string>TilezPopoverCheck</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$TILEZ_FIXTURE"
printf 'Built native regression fixture: %s\n' "$TILEZ_FIXTURE"
