#!/bin/bash
# Official signing tools matching the Sparkle version pinned in Package.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=2.10.0
SHA256=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
DEST=build/sparkle-tools
[ -x "$DEST/bin/generate_appcast" ] && exit 0
mkdir -p build
ARCHIVE=$(mktemp build/sparkle-XXXXXX.tar.xz)
trap 'rm -f "$ARCHIVE"' EXIT
curl --fail --location --retry 3 \
  "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz" -o "$ARCHIVE"
echo "$SHA256  $ARCHIVE" | shasum -a 256 -c -
mkdir -p "$DEST"
tar -xf "$ARCHIVE" -C "$DEST"
