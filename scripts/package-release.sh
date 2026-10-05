#!/bin/bash
# Builds release artifacts in build/release/:
#   Vaulto-Note-<version>.dmg  — drag-to-Applications window (main download)
#   Vaulto-Note-<version>.zip  — plain zip of the app
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(cat VERSION)
IDENTITY="${SIGN_IDENTITY:-Vaulto Note Dev}"
scripts/build-app.sh >/dev/null
mkdir -p build/release
APP="build/Vaulto Note.app"

ZIP="build/release/Vaulto-Note-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# dmgbuild lays out the window via .DS_Store directly, no Finder scripting needed.
VENV=build/.dmgvenv
[ -x "$VENV/bin/dmgbuild" ] || { python3 -m venv "$VENV" && "$VENV/bin/pip" install -q dmgbuild; }
if [ ! -f Resources/dmg-background.tiff ] || [ scripts/make-dmg-background.swift -nt Resources/dmg-background.tiff ]; then
  swift scripts/make-dmg-background.swift build/dmg-bg.png build/dmg-bg@2x.png
  tiffutil -cathidpicheck build/dmg-bg.png build/dmg-bg@2x.png -out Resources/dmg-background.tiff
fi
DMG="build/release/Vaulto-Note-$VERSION.dmg"
rm -f "$DMG"
"$VENV/bin/dmgbuild" -s scripts/dmg-settings.py -D app="$APP" -D background=Resources/dmg-background.tiff \
  "Vaulto Note" "$DMG" >/dev/null
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  codesign --force --sign "$IDENTITY" --identifier com.vaultonote.mac.dmg "$DMG"
fi

shasum -a 256 "$DMG" "$ZIP"
