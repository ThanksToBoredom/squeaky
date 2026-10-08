#!/bin/bash
# Builds a release Squeaky.app and wraps it in dist/Squeaky.dmg for sharing.
# The disk image has the app and an Applications shortcut, so it installs by drag and drop.
# Apple Silicon only (the build host's architecture).
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh release

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto build/Squeaky.app "$STAGING/Squeaky.app"
ln -s /Applications "$STAGING/Applications"

mkdir -p dist
rm -f dist/Squeaky.dmg
hdiutil create -volname "Squeaky" -srcfolder "$STAGING" -ov -format UDZO dist/Squeaky.dmg >/dev/null

echo "Packaged dist/Squeaky.dmg"
