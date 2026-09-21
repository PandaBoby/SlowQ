#!/bin/bash
# SlowQ 打包脚本:构建 release 版本并打包为 SlowQ.app
set -e
cd "$(dirname "$0")/SlowQ"

xcrun swift build -c release

APP="SlowQ.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/SlowQ "$APP/Contents/MacOS/SlowQ"
mkdir -p "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>SlowQ</string>
    <key>CFBundleDisplayName</key><string>SlowQ</string>
    <key>CFBundleIdentifier</key><string>com.slowq.app</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>SlowQ</string>
    <key>LSUIElement</key><true/>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHumanReadableCopyright</key><string>SlowQ — 防误触 ⌘Q</string>
</dict>
</plist>
PLIST

# 用稳定的 identifier 做 adhoc 签名。
# 注意:重新构建后二进制变化可能使辅助功能授权失效,若失效请运行:
#   tccutil reset Accessibility com.slowq.app
# 然后重新打开 SlowQ 并在系统设置中重新勾选。
codesign -s - --force --identifier com.slowq.app "$APP"

echo "✅ 已生成 $APP"
