#!/bin/bash
# Checks signing credentials before building a public release.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

IDENTITY="${SIGN_IDENTITY:-$(scripts/signing-identity.sh)}"
case "$IDENTITY" in
  "Developer ID Application:"*) ;;
  *)
    echo "No Developer ID Application identity is available to this process." >&2
    echo "In Xcode: Settings → Accounts → your team → Manage Certificates → + → Developer ID Application." >&2
    echo "If it already exists, run this check in Terminal with access to your login Keychain." >&2
    exit 1 ;;
esac
if ! security find-identity -v -p codesigning | grep -Fq "\"$IDENTITY\""; then
  echo "Signing identity is unavailable or has no usable private key: $IDENTITY" >&2
  exit 1
fi
echo "Signing identity: $IDENTITY"

PROFILE="${NOTARY_PROFILE:-vaulto-notary}"
echo "Checking Apple notarization credentials ($PROFILE)..."
if ! xcrun notarytool history --keychain-profile "$PROFILE" --output-format json >/dev/null; then
  echo "Cannot authenticate with Apple. In Terminal, store credentials with:" >&2
  echo "DEVELOPER_DIR=\"$DEVELOPER_DIR\" xcrun notarytool store-credentials \"$PROFILE\" --apple-id <Apple-ID> --team-id <Team-ID>" >&2
  echo "Enter the app-specific password at the secure prompt; see docs/updates.md." >&2
  exit 1
fi

scripts/fetch-sparkle-tools.sh
if [ -n "${SPARKLE_ED_KEY_FILE:-}" ]; then
  [ -s "$SPARKLE_ED_KEY_FILE" ] || { echo "Sparkle private-key file is missing or empty." >&2; exit 1; }
  echo "Sparkle key file is present; packaging will verify its signature against the embedded public key."
else
  ACCOUNT="${SPARKLE_KEY_ACCOUNT:-com.vaultonote.mac.sparkle}"
  PUBLIC_KEY=$(build/sparkle-tools/bin/generate_keys --account "$ACCOUNT" -p)
  EXPECTED_KEY=$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' Resources/Info.plist)
  if [ "$PUBLIC_KEY" != "$EXPECTED_KEY" ]; then
    echo "Sparkle signing key does not match Resources/Info.plist. Restore the existing release key." >&2
    exit 1
  fi
  echo "Sparkle public key matches the app."
fi
echo "Release credentials are ready. Run scripts/package-release.sh to build and notarize."
