#!/bin/bash
# Builds Tally.zip and Tally.dmg for people who aren't building from source.
#
# Apple silicon only (M1 and up) — same as ./build.sh, but it also stamps the
# build id the in-app updater compares against, verifies the signature, and
# packages the result. GitHub Actions runs this on every push to main and
# publishes both files as a release; the Update button fetches the zip.
#
# Signing: ad-hoc by default, which is free but makes Gatekeeper warn on the
# receiving Mac — see "Sharing it" in the README. If you have an Apple Developer
# account, set DEVID to your identity and it signs properly instead:
#
#   DEVID="Developer ID Application: Your Name (TEAMID)" ./release.sh
#
set -euo pipefail
cd "$(dirname "$0")"

APP="Tally.app"
ZIP="Tally.zip"
SIGN="${DEVID:--}"

echo "→ compiling (arm64)"
swift build -c release --arch arm64 >/dev/null

echo "→ assembling bundle"
rm -rf "$APP" "$ZIP"
mkdir -p "$APP/Contents/MacOS"
cp .build/arm64-apple-macosx/release/Tally "$APP/Contents/MacOS/Tally"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# The updater treats the latest release tag ending in this id as "current".
# Deliberately no TallySourceRepo here — an installed copy has no checkout.
BUILD="$(git rev-parse --short=7 HEAD 2>/dev/null || echo dev)"
/usr/libexec/PlistBuddy -c "Add :TallyBuild string $BUILD" "$APP/Contents/Info.plist" >/dev/null
echo "  build id: $BUILD"

echo "→ signing as: $SIGN"
codesign --force --sign "$SIGN" --options runtime --timestamp=none \
  --entitlements Resources/Tally.entitlements \
  --identifier xyz.polify.tally "$APP"

codesign --verify --strict "$APP" && echo "  signature valid"
echo "  architectures: $(lipo -archs "$APP/Contents/MacOS/Tally")"

echo "→ zipping with install instructions"
# Ship INSTALL.md alongside the app so the steps travel with the download.
rm -rf .dist && mkdir -p .dist/Tally
cp -R "$APP" .dist/Tally/
cp INSTALL.md .dist/Tally/
ditto -c -k --sequesterRsrc --keepParent .dist/Tally "$ZIP"
rm -rf .dist

echo "→ building disk image"
DMG="Tally.dmg"
rm -rf .dmg "$DMG" && mkdir -p .dmg
cp -R "$APP" .dmg/
ln -s /Applications .dmg/Applications
cp INSTALL.md .dmg/
hdiutil create -volname Tally -srcfolder .dmg -ov -format UDZO -quiet "$DMG"
rm -rf .dmg

echo
echo "✓ $ZIP  ($(du -h "$ZIP" | cut -f1))   ← what the Update button downloads"
echo "✓ $DMG  ($(du -h "$DMG" | cut -f1))   ← what you send for a first install"
if [ "$SIGN" = "-" ]; then
  echo
  echo "  Ad-hoc signed. Whoever you send it to must approve it once in"
  echo "  System Settings › Privacy & Security › Open Anyway."
  echo "  See README › Sharing it."
fi
