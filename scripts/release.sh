#!/bin/bash
# Publish a Tilez release: bash scripts/release.sh 2.1.0
# Builds, signs with Developer ID, notarizes dist.noindex/Tilez.dmg, writes the Sparkle update feed
# (dist.noindex/appcast.xml), tags v2.1.0, and creates the GitHub release with both files.
# One-time setup is in the README (Release a DMG). Override with TILEZ_SIGN_IDENTITY or TILEZ_NOTARY_PROFILE.
set -euo pipefail
TILEZ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TILEZ_ROOT"
VERSION="${1:-}"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: bash scripts/release.sh 2.1.0" >&2
  exit 1
fi
TAG="v$VERSION"
REPO="YisroelArnson/Tilez"
PROFILE="${TILEZ_NOTARY_PROFILE:-tilez-notary}"
IDENTITY="${TILEZ_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ { print $2; exit }')}"
SPARKLE_VERSION="2.10.0"
SPARKLE_TOOLS="$TILEZ_ROOT/.build/sparkle-$SPARKLE_VERSION/bin"

# Refuse anything that would make the release differ from the code on GitHub.
fail() { echo "$1" >&2; exit 1; }
[ -n "$IDENTITY" ] || fail "No Developer ID Application certificate is in your keychain (README → Release a DMG)."
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 || fail "Notarization credentials \"$PROFILE\" aren't saved (README → Release a DMG)."
gh auth status >/dev/null 2>&1 || fail "Sign in to GitHub first: gh auth login"
[ -z "$(git status --porcelain)" ] || fail "Commit or discard your changes first, so the release matches a commit."
! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || fail "$TAG already exists. Choose a higher version."
git fetch -q origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || fail "Push main first; the release is built from the pushed commit."

if [ ! -x "$SPARKLE_TOOLS/sign_update" ]; then
  mkdir -p "$TILEZ_ROOT/.build/sparkle-$SPARKLE_VERSION"
  curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
    | tar -xJ -C "$TILEZ_ROOT/.build/sparkle-$SPARKLE_VERSION"
fi

TILEZ_RELEASE=1 TILEZ_VERSION="$VERSION" bash "$TILEZ_ROOT/scripts/build.sh"
APP="$TILEZ_ROOT/dist.noindex/Tilez.app"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")"
DMG="$TILEZ_ROOT/dist.noindex/Tilez.dmg"

# Sign inside-out with the hardened runtime and a secure timestamp, as notarization requires.
echo "Signing with $IDENTITY"
sign() { codesign --force --options runtime --timestamp --sign "$IDENTITY" "$@"; }
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
sign "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
sign "$SPARKLE/Versions/B/Autoupdate"
sign "$SPARKLE/Versions/B/Updater.app"
sign "$SPARKLE"
sign "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Tilez.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname Tilez -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

echo "Submitting to Apple for notarization (usually a few minutes)…"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"

# Sparkle checks this signature (made with the private key in your keychain) before installing.
SIGNATURE="$("$SPARKLE_TOOLS/sign_update" "$DMG")"
cat > "$TILEZ_ROOT/dist.noindex/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Tilez</title>
    <item>
      <title>Tilez $VERSION</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <link>https://github.com/$REPO/releases/tag/$TAG</link>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure url="https://github.com/$REPO/releases/download/$TAG/Tilez.dmg" $SIGNATURE type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML

git tag -a "$TAG" -m "Tilez $VERSION"
git push -q origin "$TAG"
gh release create "$TAG" "$DMG" "$TILEZ_ROOT/dist.noindex/appcast.xml" --repo "$REPO" --title "Tilez $VERSION" --generate-notes
printf 'Released %s (build %s): https://github.com/%s/releases/tag/%s\n' "$VERSION" "$BUILD" "$REPO" "$TAG"
