#!/bin/bash
# Builds LaunchDeck.app into ./build (ad-hoc signed, arm64).
set -euo pipefail
cd "$(dirname "$0")"

APP="build/LaunchDeck.app"
BIN="$APP/Contents/MacOS/LaunchDeck"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> compiling (SwiftPM, release)"
swift build -c release
cp ".build/release/LaunchDeck" "$BIN"

cp Resources/Info.plist "$APP/Contents/Info.plist"

if [ ! -f Resources/AppIcon.icns ]; then
    echo "==> drawing app icon"
    swift makeicon.swift build/icon-1024.png >/dev/null
    rm -rf build/LaunchDeck.iconset
    mkdir -p build/LaunchDeck.iconset
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" build/icon-1024.png --out "build/LaunchDeck.iconset/icon_${size}x${size}.png" >/dev/null
        double=$((size * 2))
        sips -z "$double" "$double" build/icon-1024.png --out "build/LaunchDeck.iconset/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns build/LaunchDeck.iconset -o Resources/AppIcon.icns
fi

cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "==> signing (ad-hoc)"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "==> built $APP"
