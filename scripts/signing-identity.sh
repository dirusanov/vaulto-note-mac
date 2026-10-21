#!/bin/bash
# Prints the code-signing identity for builds: the first "Developer ID Application"
# certificate in the Keychain, otherwise "Vaulto Note Dev" (see create-dev-cert.sh).
set -euo pipefail
DEVELOPER_ID=$(security find-identity -v -p codesigning \
  | sed -n 's/.*"\(Developer ID Application: .*\)"$/\1/p' | head -n 1)
echo "${DEVELOPER_ID:-Vaulto Note Dev}"
