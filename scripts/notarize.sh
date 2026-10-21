#!/bin/bash
# Notarizes a Developer ID signed .app or .dmg with Apple and staples the ticket.
#
#   scripts/notarize.sh "build/Vaulto Note.app"
#   scripts/notarize.sh build/release/Vaulto-Note-0.1.1.dmg
#   scripts/notarize.sh "build/Vaulto Note.app" <existing-submission-id>
#
# Uses the notarytool Keychain profile NOTARY_PROFILE (default "vaulto-notary"),
# created once with `xcrun notarytool store-credentials`; see docs/updates.md.
set -euo pipefail
TARGET="${1:?usage: scripts/notarize.sh <path.app|path.dmg> [submission-id]}"
ID="${2:-}"
PROFILE="${NOTARY_PROFILE:-vaulto-notary}"
POLL_INTERVAL="${NOTARY_POLL_INTERVAL:-30}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
[ "$#" -le 2 ] && [ -e "$TARGET" ] || { echo "Invalid arguments or missing target: $TARGET" >&2; exit 1; }
case "$TARGET" in *.app|*.dmg) ;; *) echo "Unsupported file: $TARGET" >&2; exit 1 ;; esac
case "$POLL_INTERVAL" in ''|*[!0-9]*) echo "NOTARY_POLL_INTERVAL must be an integer." >&2; exit 1 ;; esac
if [ -n "$ID" ] && ! [[ "$ID" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]]; then
  echo "Invalid submission ID: $ID" >&2
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
LOG_DIR="${NOTARY_LOG_DIR:-build/notarization}"
mkdir -p "$LOG_DIR"
RESULT="$LOG_DIR/$(basename "$TARGET")-$(date -u +%Y%m%dT%H%M%SZ)-$$.json"

if [ -z "$ID" ]; then
  case "$TARGET" in
    *.app)
      UPLOAD="$TMP/$(basename "$TARGET" .app).zip"
      ditto -c -k --sequesterRsrc --keepParent "$TARGET" "$UPLOAD" ;;
    *.dmg) UPLOAD="$TARGET" ;;
  esac
  echo "Submitting $(basename "$TARGET") to Apple..."
  # Save the ID immediately. Never retry uploads automatically: a lost response
  # could otherwise create a duplicate request already queued by Apple.
  SUBMIT_EXIT=0
  xcrun notarytool submit "$UPLOAD" --keychain-profile "$PROFILE" \
    --output-format json > "${RESULT%.json}-submission.json" || SUBMIT_EXIT=$?
  ID=$(/usr/bin/plutil -extract id raw -o - "${RESULT%.json}-submission.json" 2>/dev/null || true)
  if [ -z "$ID" ]; then
    echo "Upload failed (exit $SUBMIT_EXIT). Check notarytool history before submitting again." >&2
    exit 1
  fi
fi
printf '%s\n' "$ID" > "${RESULT%.json}-submission-id.txt"
echo "Waiting for Apple (submission $ID). Results: $RESULT"

LAST_STATUS=""
while true; do
  if ! xcrun notarytool info "$ID" --keychain-profile "$PROFILE" \
      --output-format json > "$TMP/info.json" 2> "$TMP/error.log"; then
    cat "$TMP/error.log" >&2
    cat "$TMP/error.log" >> "${RESULT%.json}-errors.log"
    if grep -Eq 'HTTP status code: (400|401|403|404)|No Keychain password item' "$TMP/error.log"; then
      echo "Cannot access submission $ID; check the profile and submission ID." >&2
      exit 1
    fi
    echo "Status check interrupted; retrying the same submission in $POLL_INTERVAL seconds."
    sleep "$POLL_INTERVAL"
    continue
  fi
  cp "$TMP/info.json" "$RESULT"
  STATUS=$(/usr/bin/plutil -extract status raw -o - "$RESULT")
  if [ "$STATUS" != "$LAST_STATUS" ]; then
    echo "Apple status: $STATUS (submission $ID)"
    LAST_STATUS="$STATUS"
  fi
  case "$STATUS" in
    Accepted) break ;;
    "In Progress") sleep "$POLL_INTERVAL" ;;
    Invalid|Rejected)
      if xcrun notarytool log "$ID" --keychain-profile "$PROFILE" "${RESULT%.json}-log.json"; then
        cat "${RESULT%.json}-log.json" >&2
      fi
      exit 1 ;;
    *) echo "Unexpected Apple status: $STATUS" >&2; exit 1 ;;
  esac
done

# Retain Apple's report and tolerate a short ticket propagation/network delay.
xcrun notarytool log "$ID" --keychain-profile "$PROFILE" "${RESULT%.json}-log.json" || true
for ATTEMPT in {1..10}; do
  if xcrun stapler staple "$TARGET" && xcrun stapler validate "$TARGET"; then
    echo "Notarized and stapled $TARGET (submission $ID)"
    exit 0
  fi
  echo "Ticket unavailable; retrying stapling in $POLL_INTERVAL seconds ($ATTEMPT/10)."
  sleep "$POLL_INTERVAL"
done
echo "Could not staple accepted submission $ID. Resume with the same ID." >&2
exit 1
