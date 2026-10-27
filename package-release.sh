#!/bin/bash
# Build an Apple Silicon macOS app archive for GitHub Releases.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="HideNotch"
BUNDLE_ID="app.hidenotch.desktop"
RELEASE_TAG="${VERSION:-v1.2}"
VERSION="${RELEASE_TAG#v}"
BUILD_DIR="$ROOT/dist"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

rm -rf "$BUILD_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"

xcrun swiftc -O -target "arm64-apple-macos12.0" \
    "$ROOT/src/main.swift" -o "$APP_DIR/Contents/MacOS/$APP_NAME" -framework Cocoa

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>         <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>           <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>           <string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key>           <string>APPL</string>
    <key>CFBundleShortVersionString</key>    <string>$VERSION</string>
    <key>CFBundleVersion</key>               <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>        <string>12.0</string>
    <key>LSUIElement</key>                   <true/>
    <key>NSHighResolutionCapable</key>       <true/>
    <key>LSArchitecturePriority</key>
    <array><string>arm64</string></array>
</dict>
</plist>
PLIST

# Ad-hoc signing keeps the app bundle structurally valid; it is not Developer ID notarization.
codesign --force --deep --sign - "$APP_DIR"
ditto -c -k --norsrc --keepParent "$APP_DIR" \
    "$BUILD_DIR/$APP_NAME-$RELEASE_TAG-macos-arm64.zip"

echo "Created $BUILD_DIR/$APP_NAME-$RELEASE_TAG-macos-arm64.zip"
