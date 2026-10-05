#!/bin/bash
# Builds build/Vaulto Note.app from the Swift package.
#
#   scripts/build-app.sh            # build
#   scripts/build-app.sh --install  # build and copy to ~/Applications
#
# Signs with the "Vaulto Note Dev" identity when it exists (see create-dev-cert.sh),
# otherwise ad-hoc. With ad-hoc signing macOS treats every rebuild as a new app and
# asks for Accessibility again.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)
APP="$ROOT/build/Vaulto Note.app"
IDENTITY="${SIGN_IDENTITY:-Vaulto Note Dev}"
VERSION=$(cat VERSION)

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

if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  SIGN="$IDENTITY"
else
  echo "warning: signing identity '$IDENTITY' not found, signing ad-hoc" >&2
  SIGN="-"
fi
codesign --force --sign "$SIGN" "$APP/Contents/Frameworks/whisper.framework"
codesign --force --sign "$SIGN" --identifier com.vaultonote.mac "$APP"
codesign --verify --strict "$APP"
echo "Built $APP ($VERSION, signed: $SIGN)"

if [ "${1:-}" = "--install" ]; then
  mkdir -p "$HOME/Applications"
  pkill -x VaultoNote 2>/dev/null || true
  rm -rf "$HOME/Applications/Vaulto Note.app"
  cp -R "$APP" "$HOME/Applications/"
  echo "Installed to ~/Applications/Vaulto Note.app"
fi
