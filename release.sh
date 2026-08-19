#!/bin/bash
# Builds a Tally.zip you can send to someone else.
#
# Apple silicon only (M1 and up) — same as ./build.sh, but it also verifies the
# signature and wraps the result in a zip that preserves it.
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

echo
echo "✓ $ZIP  ($(du -h "$ZIP" | cut -f1))"
if [ "$SIGN" = "-" ]; then
  echo
  echo "  Ad-hoc signed. Whoever you send it to must approve it once in"
  echo "  System Settings › Privacy & Security › Open Anyway."
  echo "  See README › Sharing it."
fi
