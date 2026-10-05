#!/bin/bash
# Downloads the prebuilt whisper.cpp XCFramework (Metal-enabled) into Vendor/.
set -euo pipefail

cd "$(dirname "$0")/.."
TAG="${WHISPER_TAG:-b5130}"
mkdir -p Vendor
curl -fL -o Vendor/whisper.zip \
  "https://github.com/ggml-org/whisper.cpp/releases/download/$TAG/whisper-$TAG-xcframework.zip"
rm -rf Vendor/whisper.xcframework Vendor/build-apple
unzip -q Vendor/whisper.zip -d Vendor
mv Vendor/build-apple/whisper.xcframework Vendor/
rm -rf Vendor/build-apple Vendor/whisper.zip
echo "whisper.cpp $TAG -> Vendor/whisper.xcframework"
