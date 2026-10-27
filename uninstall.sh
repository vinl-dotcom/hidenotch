#!/bin/bash
# 卸载 HideNotch：停止 agent、还原原始壁纸、删除所有文件
set -uo pipefail

LABEL="app.hidenotch.agent"
LEGACY_LABEL="com.$(id -un).hidenotch"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
APP="$HOME/Applications/HideNotch.app"
SUPPORT="$HOME/Library/Application Support/HideNotch"
SOURCE_RECORD="$SUPPORT/source.txt"

echo "==> 停止并卸载 LaunchAgent"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$PLIST"
launchctl bootout "gui/$(id -u)/$LEGACY_LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LEGACY_LABEL.plist"

echo "==> 结束残留进程"
pkill -f "HideNotch.app/Contents/MacOS/HideNotch" 2>/dev/null || true

# 还原用户原始壁纸
if [ -f "$SOURCE_RECORD" ]; then
    ORIG="$(cat "$SOURCE_RECORD")"
    if [ -n "$ORIG" ] && [ -f "$ORIG" ]; then
        echo "==> 还原原始壁纸：$ORIG"
        osascript -e "tell application \"System Events\" to tell every desktop to set picture to \"$ORIG\"" 2>/dev/null || true
    fi
fi

echo "==> 删除文件"
rm -rf "$APP"
rm -rf "$SUPPORT"

echo "==> 已卸载。若菜单栏黑条仍在，请到 系统设置 > 壁纸 手动重选一张壁纸。"
