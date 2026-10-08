#!/bin/bash
# Creates a self-signed code-signing certificate ("Squeaky Local Signing") in your login keychain.
#
# macOS ties privacy permissions such as Full Disk Access to an app's code signature. Ad-hoc
# signatures change on every build, so the permission would be lost after each rebuild.
# Signing with this certificate keeps the signature stable. Run once; macOS will ask you to
# confirm adding the certificate to your keychain and trusting it for code signing.
#
# To undo: open Keychain Access and delete the "Squeaky Local Signing" certificate and key.
set -euo pipefail

NAME="Squeaky Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "\"$NAME\" already exists."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

# The system LibreSSL writes PKCS#12 files that `security import` understands.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$TMP/cert.cnf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$NAME" -out "$TMP/cert.p12" -passout pass:squeaky

security import "$TMP/cert.p12" -k "$KEYCHAIN" -P squeaky -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

echo "Created \"$NAME\". scripts/build-app.sh will now sign with it."
