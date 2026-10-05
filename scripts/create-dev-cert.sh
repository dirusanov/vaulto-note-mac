#!/bin/bash
# Creates a self-signed code-signing identity "Vaulto Note Dev" in the login keychain.
# A stable identity keeps macOS privacy permissions (Accessibility, Microphone) across
# rebuilds; ad-hoc signatures change with every build.
set -euo pipefail

NAME="Vaulto Note Dev"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "'$NAME' already exists"
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" 2>/dev/null
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/cert.p12" -passout pass:vaulto 2>/dev/null \
  || openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
       -out "$TMP/cert.p12" -passout pass:vaulto
security import "$TMP/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
  -P vaulto -T /usr/bin/codesign
echo "Created '$NAME'"
