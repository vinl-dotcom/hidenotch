#!/bin/bash
# 安装并启用开机自启的 LaunchAgent
set -euo pipefail

LABEL="app.hidenotch.agent"
LEGACY_LABEL="com.$(id -un).hidenotch"
EXE="$HOME/Applications/HideNotch.app/Contents/MacOS/HideNotch"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [ ! -x "$EXE" ]; then
    echo "找不到可执行文件：$EXE"
    echo "请先运行 bash build.sh"
    exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents"
# Remove the per-user label used by earlier builds.
launchctl bootout "gui/$(id -u)/$LEGACY_LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LEGACY_LABEL.plist"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>            <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$EXE</string>
    </array>
    <key>RunAtLoad</key>        <true/>
    <key>KeepAlive</key>        <true/>
    <key>ProcessType</key>      <string>Interactive</string>
</dict>
</plist>
PLIST

# 重新加载（先 bootout 忽略报错，再 bootstrap）
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "==> 已启用开机自启：$LABEL"
echo "    查看状态：launchctl print gui/$(id -u)/$LABEL | head"
