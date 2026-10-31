#!/bin/bash
# Builds Squeaky.app into ./build. Usage: scripts/build-app.sh [debug|release]
# UNIVERSAL=1 builds for both Apple Silicon and Intel and merges them into one binary.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
# The default (swift-build) backend currently fails to initialise with the
# Command Line Tools on macOS 27, so use the native one where SwiftPM offers the choice.
BUILD=(swift build -c "$CONFIG")
if swift build --help 2>&1 | grep -q -- '--build-system'; then
    BUILD+=(--build-system native)
fi

if [ "${UNIVERSAL:-0}" = "1" ]; then
    BIN_DIR="$(mktemp -d)"
    SLICES=()
    for arch in arm64 x86_64; do
        "${BUILD[@]}" --triple "$arch-apple-macosx15.0"
        SLICES+=("$("${BUILD[@]}" --triple "$arch-apple-macosx15.0" --show-bin-path 2>/dev/null)/Squeaky")
    done
    lipo -create "${SLICES[@]}" -output "$BIN_DIR/Squeaky"
else
    "${BUILD[@]}"
    BIN_DIR="$("${BUILD[@]}" --show-bin-path 2>/dev/null)"
fi

if [ ! -f Resources/AppIcon.icns ]; then
    swift scripts/make-icon.swift Resources/AppIcon.icns
fi

APP="build/Squeaky.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Squeaky" "$APP/Contents/MacOS/Squeaky"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Art/*.svg Resources/Art/*LICENSE* "$APP/Contents/Resources/"
# A stable identity keeps Full Disk Access across rebuilds; see scripts/create-signing-cert.sh.
# "Cleen Local Signing" is the certificate's name from before the app was renamed; still accepted.
IDENTITY=""
for name in "Squeaky Local Signing" "Cleen Local Signing"; do
    if security find-certificate -c "$name" >/dev/null 2>&1; then IDENTITY="$name"; break; fi
done
if [ -n "$IDENTITY" ]; then
    codesign --force --sign "$IDENTITY" "$APP" >/dev/null
else
    codesign --force --sign - "$APP" >/dev/null
    echo "note: signed ad-hoc; Full Disk Access will need re-granting after each rebuild." \
         "Run scripts/create-signing-cert.sh once to fix that."
fi

echo "Built $APP"
