#!/bin/bash
# Builds build/Vaulto Note.app from the Swift package.
#
#   scripts/build-app.sh            # build
#   scripts/build-app.sh --install  # build and copy to ~/Applications
#
# Signs with SIGN_IDENTITY when set, otherwise with the first "Developer ID Application"
# identity in the Keychain (public releases, see docs/updates.md), then "Vaulto Note Dev"
# (see create-dev-cert.sh), then ad-hoc. With ad-hoc signing macOS treats every rebuild
# as a new app and asks for Accessibility again.
set -euo pipefail
umask 022

cd "$(dirname "$0")/.."
ROOT=$(pwd)
APP="$ROOT/build/Vaulto Note.app"
VERSION=$(cat VERSION)
IDENTITY="${SIGN_IDENTITY:-$(scripts/signing-identity.sh)}"
if [ "$IDENTITY" = "-" ]; then
  SIGN="-"
elif security find-identity -v -p codesigning | grep -Fq "\"$IDENTITY\""; then
  SIGN="$IDENTITY"
elif [ -n "${SIGN_IDENTITY:-}" ]; then
  echo "Requested signing identity is unavailable or has no usable private key: $IDENTITY" >&2
  exit 1
else
  echo "warning: no signing identity found, signing ad-hoc" >&2
  SIGN="-"
fi

if [ ! -d Vendor/whisper.xcframework ]; then
  scripts/fetch-whisper.sh
fi

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swift build -c release
BIN=$(swift build -c release --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp "$BIN/VaultoNote" "$APP/Contents/MacOS/VaultoNote"
cp -R "$BIN/whisper.framework" "$APP/Contents/Frameworks/"
ditto "$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" \
  "$APP/Contents/Frameworks/Sparkle.framework"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"

# App icon: the mobile app's glyph on Apple's icon grid (scripts/make-icon.swift).
if [ ! -f build/AppIcon.icns ] || [ Resources/AppIcon-1024.png -nt build/AppIcon.icns ]; then
  ICONSET=build/AppIcon.iconset
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) Resources/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o build/AppIcon.icns
  rm -rf "$ICONSET"
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/*.lproj "$APP/Contents/Resources/"

# A signing job may run under a private umask (077), including the Swift build
# cache. Public app bundles must remain readable/executable for other Mac users.
chmod -R go-w,a+rX "$APP"

# Notarization needs a secure timestamp and the hardened runtime on the app. Local
# builds skip both: without a Team ID, runtime library validation rejects whisper.framework.
case "$SIGN" in
  "Developer ID Application"*)
    STAMP=--timestamp
    APP_RUNTIME=(--options runtime --entitlements Resources/VaultoNote.entitlements) ;;
  *)
    STAMP=--timestamp=none
    APP_RUNTIME=() ;;
esac
codesign --force --sign "$SIGN" $STAMP --options runtime "$APP/Contents/Frameworks/whisper.framework"
# Sparkle's installer and downloader must retain their entitlements and be
# signed from the inside out. --deep signing can silently break the helpers.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$SIGN" $STAMP --options runtime "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
codesign --force --sign "$SIGN" $STAMP --options runtime --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
codesign --force --sign "$SIGN" $STAMP --options runtime "$SPARKLE/Versions/B/Autoupdate"
codesign --force --sign "$SIGN" $STAMP --options runtime "$SPARKLE/Versions/B/Updater.app"
codesign --force --sign "$SIGN" $STAMP --options runtime "$SPARKLE"
codesign --force --sign "$SIGN" $STAMP ${APP_RUNTIME[@]+"${APP_RUNTIME[@]}"} --identifier com.vaultonote.mac "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP ($VERSION, signed: $SIGN)"

if [ "${1:-}" = "--install" ]; then
  mkdir -p "$HOME/Applications"
  pkill -x VaultoNote 2>/dev/null || true
  rm -rf "$HOME/Applications/Vaulto Note.app"
  cp -R "$APP" "$HOME/Applications/"
  echo "Installed to ~/Applications/Vaulto Note.app"
fi
