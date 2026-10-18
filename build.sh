#!/bin/bash
# Build MacSwitch.app — no Xcode required, just Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

APP="MacSwitch.app"
BIN="MacSwitch"

echo "==> Compiling SwiftUI sources"
swiftc -O -target arm64-apple-macos14.0 -o "$BIN" Sources/*.swift

echo "==> Bundling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$BIN"
cp Info.plist "$APP/Contents/Info.plist"

if [ ! -f "$APP/Contents/Resources/AppIcon.icns" ]; then
    echo "==> Generating app icon"
    mkdir -p build
    swift Tools/make_icon.swift Assets/IconSource.png build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc sign so Gatekeeper treats it as a normal local app.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "==> Done. Launch with:  open $APP"
