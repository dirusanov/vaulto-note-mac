#!/bin/bash
# Builds release artifacts in build/release/:
#   Vaulto-Note-<version>.dmg  — drag-to-Applications window (main download)
#   Vaulto-Note-<version>.zip  — plain zip of the app
#   appcast.xml               — signed Sparkle feed (publish with both archives)
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(cat VERSION)
IDENTITY="${SIGN_IDENTITY:-Vaulto Note Dev}"
SPARKLE_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-com.vaultonote.mac.sparkle}"
SIGNING_ARGS=(--account "$SPARKLE_ACCOUNT")
if [ -n "${SPARKLE_ED_KEY_FILE:-}" ]; then
  SIGNING_ARGS+=(--ed-key-file "$SPARKLE_ED_KEY_FILE")
fi
ARCHIVES_ONLY=false
case "${1:-}" in
  "") ;;
  --archives-only) ARCHIVES_ONLY=true ;;
  *) echo "Usage: scripts/package-release.sh [--archives-only]" >&2; exit 1 ;;
esac
scripts/fetch-sparkle-tools.sh
# Refuse a release that cannot be signed with the key trusted by installed apps.
if [ "$ARCHIVES_ONLY" = false ] && [ -z "${SPARKLE_ED_KEY_FILE:-}" ]; then
  PUBLIC_KEY=$(build/sparkle-tools/bin/generate_keys --account "$SPARKLE_ACCOUNT" -p)
  EXPECTED_KEY=$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' Resources/Info.plist)
  if [ "$PUBLIC_KEY" != "$EXPECTED_KEY" ]; then
    echo "Sparkle signing key is missing or does not match Resources/Info.plist." >&2
    echo "Restore the release key to your login Keychain; see docs/updates.md." >&2
    exit 1
  fi
fi
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

if [ "$ARCHIVES_ONLY" = true ]; then
  rm -f build/release/appcast.xml
  echo "Built review archives only; no signed update feed. Run without --archives-only before publishing."
  shasum -a 256 "$DMG" "$ZIP"
  exit 0
fi

# Use the ZIP for Sparkle; DMG remains the first-install download. A separate
# directory avoids duplicate feed entries for two archives of the same version.
FEED_DIR=build/update-feed
rm -rf "$FEED_DIR"
mkdir -p "$FEED_DIR"
cp "$ZIP" "$FEED_DIR/"
if [ -f "docs/releases/$VERSION.html" ]; then
  cp "docs/releases/$VERSION.html" "$FEED_DIR/Vaulto-Note-$VERSION.html"
fi
build/sparkle-tools/bin/generate_appcast "${SIGNING_ARGS[@]}" \
  --download-url-prefix "https://github.com/dirusanov/vaulto-note-mac/releases/download/v$VERSION/" \
  --embed-release-notes --maximum-deltas 0 "$FEED_DIR"
cp "$FEED_DIR/appcast.xml" build/release/appcast.xml
swift scripts/verify-update.swift "$APP" build/release/appcast.xml "$ZIP"
shasum -a 256 "$DMG" "$ZIP" build/release/appcast.xml
