#!/bin/bash
set -euo pipefail
QUILT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$QUILT_ROOT"
mkdir -p .build/module-cache
export CLANG_MODULE_CACHE_PATH="$QUILT_ROOT/.build/module-cache"
swift build --target QuiltCore --disable-sandbox
QUILT_BIN="$(swift build --show-bin-path --disable-sandbox)"
QUILT_FIXTURE="$QUILT_ROOT/.build/Quilt Popover Check.app"
mkdir -p "$QUILT_FIXTURE/Contents/MacOS" /private/tmp/quilt-popover-check
rm -f /private/tmp/quilt-popover-check/native-regression.json
swiftc -module-cache-path "$QUILT_ROOT/.build/module-cache" -I "$QUILT_BIN/Modules" \
  "$QUILT_ROOT/Sources/WindowQuilt/MenuPopoverController.swift" "$QUILT_ROOT/Tests/PopoverFixture/main.swift" \
  "$QUILT_BIN/QuiltCore.build/"*.swift.o -o "$QUILT_FIXTURE/Contents/MacOS/QuiltPopoverCheck"
cat > "$QUILT_FIXTURE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Quilt Popover Check</string>
<key>CFBundleIdentifier</key><string>com.local.quiltpopovercheck</string>
<key>CFBundleExecutable</key><string>QuiltPopoverCheck</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$QUILT_FIXTURE"
printf 'Built native regression fixture: %s\n' "$QUILT_FIXTURE"
