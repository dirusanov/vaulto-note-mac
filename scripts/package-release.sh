#!/bin/bash
# Builds a release zip: build/release/Vaulto-Note-<version>.zip
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(cat VERSION)
scripts/build-app.sh >/dev/null
mkdir -p build/release
OUT="build/release/Vaulto-Note-$VERSION.zip"
rm -f "$OUT"
ditto -c -k --sequesterRsrc --keepParent "build/Vaulto Note.app" "$OUT"
shasum -a 256 "$OUT"
