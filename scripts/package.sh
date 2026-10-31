#!/bin/bash
# Builds a release Squeaky.app and wraps it in a disk image for sharing.
# Usage: scripts/package.sh [output.dmg]   (default: dist/Squeaky.dmg)
# The disk image has the app and an Applications shortcut, so it installs by drag and drop.
# Builds for the host's architecture only, unless UNIVERSAL=1 is set (see build-app.sh).
set -euo pipefail
cd "$(dirname "$0")/.."

DMG="${1:-dist/Squeaky.dmg}"

scripts/build-app.sh release

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto build/Squeaky.app "$STAGING/Squeaky.app"
ln -s /Applications "$STAGING/Applications"

mkdir -p "$(dirname "$DMG")"
rm -f "$DMG"
hdiutil create -volname "Squeaky" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null

echo "Packaged $DMG"
