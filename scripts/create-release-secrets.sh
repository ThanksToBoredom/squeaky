#!/bin/bash
# Creates the release signing certificate ("Squeaky Release Signing") and stores it as the
# repository secrets the Release workflow signs with: SIGNING_P12 and SIGNING_P12_PASSWORD.
# Usage: scripts/create-release-secrets.sh [owner/repo]   (needs `gh` with admin rights)
#
# The certificate is self-signed and made only for GitHub releases: it never enters your keychain
# and the key is deleted locally once uploaded. Every release then has the same signature, so
# macOS keeps permissions such as Full Disk Access across updates. Running this again replaces
# the certificate, which means users re-grant those permissions once after the next update.
set -euo pipefail

REPO="${1:-ThanksToBoredom/squeaky}"
NAME="Squeaky Release Signing"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
O = Thanks to Boredom
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

# The system LibreSSL writes PKCS#12 files that `security import` understands.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$TMP/cert.cnf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
PASSWORD="$(/usr/bin/openssl rand -base64 24)"
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$NAME" -out "$TMP/release.p12" -passout "pass:$PASSWORD"

base64 -i "$TMP/release.p12" | gh secret set SIGNING_P12 -R "$REPO"
printf '%s' "$PASSWORD" | gh secret set SIGNING_P12_PASSWORD -R "$REPO"

echo "Stored SIGNING_P12 and SIGNING_P12_PASSWORD on $REPO:"
/usr/bin/openssl x509 -in "$TMP/cert.pem" -noout -subject -enddate
