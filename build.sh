#!/bin/bash
# Builds Tally.app. Run ./build.sh, then drag Tally.app to /Applications.
set -euo pipefail

cd "$(dirname "$0")"
APP="Tally.app"

echo "→ compiling"
swift build -c release --arch arm64

echo "→ assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/arm64-apple-macosx/release/Tally "$APP/Contents/MacOS/Tally"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Stamp where this build came from, so the in-app update button knows which
# checkout to pull. Must happen before signing — the signature seals Info.plist.
# release.sh deliberately does NOT do this: a zipped copy has no repo to pull.
if [ -d .git ]; then
  /usr/libexec/PlistBuddy -c "Add :TallySourceRepo string $(pwd)" \
    "$APP/Contents/Info.plist" >/dev/null
  echo "  update source: $(pwd)"
fi

echo "→ signing"
codesign --force --sign - --options runtime \
  --entitlements Resources/Tally.entitlements \
  --identifier xyz.polify.tally "$APP"

echo
echo "✓ $APP is ready"
echo "  open $APP        — run it now"
echo "  cp -r $APP /Applications/  — install it"
