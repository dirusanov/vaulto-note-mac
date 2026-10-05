#!/bin/bash
# Regenerates README media (screenshots, GIFs, banner) from the real UI with sample data.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
scripts/build-app.sh >/dev/null
BIN="build/Vaulto Note.app/Contents/MacOS/VaultoNote"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

"$BIN" --snapshot "$TMP/snap" en ru
mkdir -p docs/screenshots
for f in light-home-result dark-home light-history light-transcription light-shortcuts dark-general \
         light-onboarding-0 light-onboarding-2 light-onboarding-4; do
  sips -Z 1400 "$TMP/snap/en-$f.png" --out "docs/screenshots/$f.png" >/dev/null
done
sips -Z 1400 "$TMP/snap/ru-light-home.png" --out docs/screenshots/ru-light-home.png >/dev/null

"$BIN" --demo "$TMP/demo"
swift scripts/make-gif.swift "$TMP/demo" "$TMP/demo/flow.txt" docs/demo.gif 1200
swift scripts/make-gif.swift "$TMP/demo" "$TMP/demo/hud.txt" docs/recording-indicator.gif

"$BIN" --banner docs/banner.png docs/screenshots/light-home-result.png
sips -z 640 1280 docs/banner.png >/dev/null
echo "docs/ updated"
