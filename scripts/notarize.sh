#!/bin/bash
# Notarizes a Developer ID signed .app or .dmg with Apple and staples the ticket.
#
#   scripts/notarize.sh "build/Vaulto Note.app"
#   scripts/notarize.sh build/release/Vaulto-Note-0.1.1.dmg
#
# Uses the notarytool Keychain profile NOTARY_PROFILE (default "vaulto-notary"),
# created once with `xcrun notarytool store-credentials`; see docs/updates.md.
set -euo pipefail
TARGET="${1:?usage: scripts/notarize.sh <path.app|path.dmg>}"
PROFILE="${NOTARY_PROFILE:-vaulto-notary}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
case "$TARGET" in
  *.app)
    UPLOAD="$TMP/$(basename "$TARGET" .app).zip"
    ditto -c -k --sequesterRsrc --keepParent "$TARGET" "$UPLOAD" ;;
  *.dmg) UPLOAD="$TARGET" ;;
  *) echo "Unsupported file: $TARGET" >&2; exit 1 ;;
esac

echo "Notarizing $(basename "$TARGET"); Apple usually answers within a few minutes..."
SUBMIT_EXIT=0
xcrun notarytool submit "$UPLOAD" --keychain-profile "$PROFILE" --wait \
  --output-format json > "$TMP/result.json" || SUBMIT_EXIT=$?
LOG_DIR="${NOTARY_LOG_DIR:-build/notarization}"
mkdir -p "$LOG_DIR"
RESULT="$LOG_DIR/$(basename "$TARGET")-$(date -u +%Y%m%dT%H%M%SZ)-$$.json"
cp "$TMP/result.json" "$RESULT"
STATUS=$(/usr/bin/plutil -extract status raw -o - "$TMP/result.json" 2>/dev/null || true)
ID=$(/usr/bin/plutil -extract id raw -o - "$TMP/result.json" 2>/dev/null || true)
echo "Notarization result saved to $RESULT"
if [ "$SUBMIT_EXIT" -ne 0 ] || [ "$STATUS" != "Accepted" ]; then
  if [ -z "$ID" ]; then
    echo "Apple submission failed (exit $SUBMIT_EXIT). Check credentials and network access." >&2
    exit 1
  fi
  echo "Notarization $STATUS (submission $ID). Apple's log:" >&2
  if xcrun notarytool log "$ID" --keychain-profile "$PROFILE" "${RESULT%.json}-log.json"; then
    cat "${RESULT%.json}-log.json" >&2
  fi
  exit 1
fi
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
echo "Notarized and stapled $TARGET (submission $ID)"
