#!/bin/bash
# SlowQ 打包脚本:构建 release 版本并打包为 SlowQ.app(含图标)
set -e
cd "$(dirname "$0")/SlowQ"

xcrun swift build -c release

APP="SlowQ.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SlowQ "$APP/Contents/MacOS/SlowQ"

# SwiftPM 资源 bundle(状态栏图标)
if [ -d ".build/release/SlowQ_SlowQ.bundle" ]; then
    cp -R .build/release/SlowQ_SlowQ.bundle "$APP/Contents/Resources/"
    echo "📦 资源 bundle 已打包"
elif [ -d ".build/out/Products/Release/SlowQ_SlowQ.bundle" ]; then
    cp -R .build/out/Products/Release/SlowQ_SlowQ.bundle "$APP/Contents/Resources/"
    echo "📦 资源 bundle 已打包(out 布局)"
fi

# ── 图标:从 iconset 生成 icns(若图标源不存在则跳过,不阻断构建)──
ICONSET_SRC="${SLOWQ_ICONSET:-$HOME/Downloads/AppIcons/Assets.xcassets/AppIcon.appiconset}"
ICONSET_TMP="$APP/Contents/Resources/AppIcon.iconset"
if [ -d "$ICONSET_SRC" ]; then
    mkdir -p "$ICONSET_TMP"
    cp "$ICONSET_SRC/16.png"    "$ICONSET_TMP/icon_16x16.png"
    cp "$ICONSET_SRC/32.png"    "$ICONSET_TMP/icon_16x16@2x.png"
    cp "$ICONSET_SRC/32.png"    "$ICONSET_TMP/icon_32x32.png"
    cp "$ICONSET_SRC/64.png"    "$ICONSET_TMP/icon_32x32@2x.png"
    cp "$ICONSET_SRC/128.png"   "$ICONSET_TMP/icon_128x128.png"
    cp "$ICONSET_SRC/256.png"   "$ICONSET_TMP/icon_128x128@2x.png"
    cp "$ICONSET_SRC/256.png"   "$ICONSET_TMP/icon_256x256.png"
    cp "$ICONSET_SRC/512.png"   "$ICONSET_TMP/icon_256x256@2x.png"
    cp "$ICONSET_SRC/512.png"   "$ICONSET_TMP/icon_512x512.png"
    cp "$ICONSET_SRC/1024.png"  "$ICONSET_TMP/icon_512x512@2x.png"
    iconutil -c icns "$ICONSET_TMP" -o "$APP/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET_TMP"
    echo "🎨 图标已集成"
else
    echo "⚠️  未找到图标源($ICONSET_SRC),跳过图标"
fi

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
    <key>CFBundleIconFile</key><string>AppIcon</string>
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
