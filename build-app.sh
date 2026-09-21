#!/bin/bash
# SlowQ 打包脚本:构建 release 版本并打包为 SlowQ.app(含 App 图标 + 菜单栏图标)
set -e
cd "$(dirname "$0")/SlowQ"

# ── 菜单栏图标:从源图标生成(裁透明边距 + 等比缩放到 17pt 高)──
# 必须在 swift build 之前,资源清单才会打到 .bundle 里
ICON_SRC="${SLOWQ_ICON:-$PWD/SlowQ.png}"
if [ -f "$ICON_SRC" ]; then
    echo "🐌 生成菜单栏图标…"
    swift ../tools/gen-statusbar.swift "$ICON_SRC" "$PWD/src/Resources"
else
    echo "⚠️  未找到图标源: $ICON_SRC"
fi

xcrun swift build -c release

APP="SlowQ.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SlowQ "$APP/Contents/MacOS/SlowQ"

# SwiftPM 资源 bundle(菜单栏图标)
if [ -d ".build/release/SlowQ_SlowQ.bundle" ]; then
    cp -R .build/release/SlowQ_SlowQ.bundle "$APP/Contents/Resources/"
    echo "📦 资源 bundle 已打包"
elif [ -d ".build/out/Products/Release/SlowQ_SlowQ.bundle" ]; then
    cp -R .build/out/Products/Release/SlowQ_SlowQ.bundle "$APP/Contents/Resources/"
    echo "📦 资源 bundle 已打包(out 布局)"
fi

# ── App 图标:从同一源图生成全尺寸 icns ──
ICONSET_TMP="$APP/Contents/Resources/AppIcon.iconset"
if [ -f "$ICON_SRC" ]; then
    IT=$(mktemp -d)
    for s in 16 32 64 128 256 512 1024; do
        sips -z $s $s "$ICON_SRC" --out "$IT/$s.png" -s format png >/dev/null
    done
    mkdir -p "$ICONSET_TMP"
    cp "$IT/16.png"   "$ICONSET_TMP/icon_16x16.png"
    cp "$IT/32.png"   "$ICONSET_TMP/icon_16x16@2x.png"
    cp "$IT/32.png"   "$ICONSET_TMP/icon_32x32.png"
    cp "$IT/64.png"   "$ICONSET_TMP/icon_32x32@2x.png"
    cp "$IT/128.png"  "$ICONSET_TMP/icon_128x128.png"
    cp "$IT/256.png"  "$ICONSET_TMP/icon_128x128@2x.png"
    cp "$IT/256.png"  "$ICONSET_TMP/icon_256x256.png"
    cp "$IT/512.png"  "$ICONSET_TMP/icon_256x256@2x.png"
    cp "$IT/512.png"  "$ICONSET_TMP/icon_512x512.png"
    cp "$IT/1024.png" "$ICONSET_TMP/icon_512x512@2x.png"
    iconutil -c icns "$ICONSET_TMP" -o "$APP/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET_TMP" "$IT"
    echo "🎨 图标已集成"
else
    echo "⚠️  未找到图标源,跳过图标"
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
