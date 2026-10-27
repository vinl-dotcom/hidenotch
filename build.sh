#!/bin/bash
# 编译 HideNotch + 打包成 .app + 安装到 ~/Applications
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="HideNotch"
BUNDLE_ID="app.hidenotch.desktop"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
INSTALL_DIR="$HOME/Applications"

echo "==> 编译 $APP_NAME"
mkdir -p "$BUILD_DIR"
swiftc -O "$ROOT/src/main.swift" -o "$BUILD_DIR/$APP_NAME" -framework Cocoa

echo "==> 组装 .app bundle"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mv "$BUILD_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>             <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>      <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>       <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>       <string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key>      <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key>          <string>1</string>
    <key>LSMinimumSystemVersion</key>   <string>12.0</string>
    <key>LSUIElement</key>              <true/>
    <key>NSHighResolutionCapable</key>  <true/>
</dict>
</plist>
PLIST

# ad-hoc 签名（Apple Silicon 上让本地构建的 app 正常运行）
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true

echo "==> 安装到 $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$APP_DIR" "$INSTALL_DIR/$APP_NAME.app"

echo "==> 完成：$INSTALL_DIR/$APP_NAME.app"
echo "    手动测试：\"$INSTALL_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME\" &"
echo "    开机自启：bash \"$ROOT/install-agent.sh\""
