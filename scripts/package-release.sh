#!/bin/bash
# Builds release artifacts in build/release/:
#   Vaulto-Note-<version>.dmg  — drag-to-Applications window (main download)
#   Vaulto-Note-<version>.zip  — plain zip of the app
#   appcast.xml               — signed Sparkle feed (publish with both archives)
# With a Developer ID identity the app and DMG are notarized by Apple and stapled,
# so they open without Gatekeeper warnings. A full release requires Developer ID.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
VERSION=$(cat VERSION)
IDENTITY="${SIGN_IDENTITY:-$(scripts/signing-identity.sh)}"
case "$IDENTITY" in
  "Developer ID Application"*) NOTARIZE=true ;;
  *) NOTARIZE=false ;;
esac
SPARKLE_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-com.vaultonote.mac.sparkle}"
SIGNING_ARGS=(--account "$SPARKLE_ACCOUNT")
if [ -n "${SPARKLE_ED_KEY_FILE:-}" ]; then
  SIGNING_ARGS+=(--ed-key-file "$SPARKLE_ED_KEY_FILE")
fi
ARCHIVES_ONLY=false
RESUME_APP_ID=""
case "${1:-}" in
  "") ;;
  --archives-only) ARCHIVES_ONLY=true ;;
  --check) exec scripts/check-release.sh ;;
  --resume-app)
    [ "$#" -eq 2 ] || { echo "Usage: scripts/package-release.sh --resume-app <submission-id>" >&2; exit 1; }
    RESUME_APP_ID="${2:?submission ID is required}" ;;
  *) echo "Usage: scripts/package-release.sh [--check|--archives-only|--resume-app <submission-id>]" >&2; exit 1 ;;
esac
if [ "$ARCHIVES_ONLY" = false ] && [ "$NOTARIZE" = false ]; then
  echo "A public release needs a Developer ID Application certificate; found '$IDENTITY'." >&2
  echo "See docs/updates.md, or use --archives-only for a local review build." >&2
  exit 1
fi
# Refuse missing Apple or updater credentials before rebuilding the app.
if [ "$ARCHIVES_ONLY" = false ]; then
  SIGN_IDENTITY="$IDENTITY" scripts/check-release.sh
fi
scripts/fetch-sparkle-tools.sh
APP="build/Vaulto Note.app"
if [ -n "$RESUME_APP_ID" ]; then
  # A rebuild would change the signed binary while Apple processes the old one.
  codesign --verify --deep --strict "$APP"
  SIGNATURE_INFO=$(codesign -d --verbose=2 "$APP" 2>&1)
  grep -Fq "Authority=$IDENTITY" <<< "$SIGNATURE_INFO" || {
    echo "Existing app is not signed by the selected Developer ID." >&2; exit 1;
  }
  APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")
  [ "$APP_VERSION" = "$VERSION" ] || { echo "Existing app version does not match VERSION." >&2; exit 1; }
  echo "Resuming submission $RESUME_APP_ID with the existing signed app."
elif [ "$NOTARIZE" = true ] || [ -n "${SIGN_IDENTITY:-}" ]; then
  SIGN_IDENTITY="$IDENTITY" scripts/build-app.sh >/dev/null
else
  scripts/build-app.sh >/dev/null
fi
mkdir -p build/release
# Staple before archiving: the Sparkle ZIP signature covers the stapled app.
if [ "$NOTARIZE" = true ]; then
  scripts/notarize.sh "$APP" "$RESUME_APP_ID"
fi

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
if [ "$NOTARIZE" = true ]; then
  codesign --force --sign "$IDENTITY" --timestamp --identifier com.vaultonote.mac.dmg "$DMG"
  scripts/notarize.sh "$DMG"
  spctl --assess --type execute --verbose "$APP"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG"
elif security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
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
