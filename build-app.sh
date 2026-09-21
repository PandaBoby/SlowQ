#!/bin/bash
# SlowQ 打包脚本:构建 release 版本并打包为 SlowQ.app(含 App 图标 + 菜单栏图标)
#
# 默认构建通用二进制(arm64 + x86_64),Intel 与 Apple Silicon 均可运行。
# 环境变量:
#   SLOWQ_ICON=path        指定图标源(默认 SlowQ/SlowQ.png)
#   SLOWQ_ICON_HEIGHT=pt   菜单栏图标内容高度(默认 15)
#   SLOWQ_NATIVE=1         只构建本机架构(更快,适合本地调试)
#   SLOWQ_VERSION=x.y.z    写入 Info.plist 的版本号(默认 1.0.0)
set -e
cd "$(dirname "$0")/SlowQ"

VERSION="${SLOWQ_VERSION:-1.0.0}"

# ── 菜单栏图标:从源图标生成(裁透明边距 + 等比缩放)──
# 必须在 swift build 之前,资源清单才会打到 .bundle 里
ICON_SRC="${SLOWQ_ICON:-$PWD/SlowQ.png}"
if [ -f "$ICON_SRC" ]; then
    echo "🐌 生成菜单栏图标…"
    swift ../tools/gen-statusbar.swift "$ICON_SRC" "$PWD/src/Resources" "${SLOWQ_ICON_HEIGHT:-15}"
else
    echo "⚠️  未找到图标源: $ICON_SRC"
fi

# ── 编译 ──
# 通用构建产物落在 .build/out/Products/Release/,单架构在 .build/release/
if [ "${SLOWQ_NATIVE:-0}" = "1" ]; then
    echo "🔨 编译(仅本机架构)…"
    xcrun swift build -c release
    BUILD_BIN=".build/release/SlowQ"
    BUILD_BUNDLE=".build/release/SlowQ_SlowQ.bundle"
else
    echo "🔨 编译(arm64 + x86_64 通用二进制)…"
    xcrun swift build -c release --arch arm64 --arch x86_64
    BUILD_BIN=".build/out/Products/Release/SlowQ"
    BUILD_BUNDLE=".build/out/Products/Release/SlowQ_SlowQ.bundle"
fi

[ -f "$BUILD_BIN" ] || { echo "❌ 未找到编译产物: $BUILD_BIN"; exit 1; }

# 产物放在隐藏目录 .build-app/ 下:Spotlight 不索引点号目录,
# 因此开发构建不会出现在 Finder 搜索 / Launchpad 里,避免与 /Applications 的正式版重复。
APP=".build-app/SlowQ.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_BIN" "$APP/Contents/MacOS/SlowQ"

# SwiftPM 资源 bundle(菜单栏图标)
if [ -d "$BUILD_BUNDLE" ]; then
    cp -R "$BUILD_BUNDLE" "$APP/Contents/Resources/"
    echo "📦 资源 bundle 已打包"
elif [ -d ".build/release/SlowQ_SlowQ.bundle" ]; then
    cp -R ".build/release/SlowQ_SlowQ.bundle" "$APP/Contents/Resources/"
    echo "📦 资源 bundle 已打包(回退路径)"
fi

# ── App 图标:从同一源图生成全尺寸 icns ──
ICONSET_TMP="$APP/Contents/Resources/AppIcon.iconset"
if [ -f "$ICON_SRC" ]; then
    IT=$(mktemp -d)
    # 先生成"保持宽高比的正方形底图":源图多为横版(如 384x256),
    # 直接 sips -z N N 会把图形压成正方形造成拉伸变形。
    # SLOWQ_APPICON_FRACTION 控制图形最长边占画布比例(默认 0.86)。
    swift ../tools/gen-appicon.swift "$ICON_SRC" "$IT/appicon-1024.png" "${SLOWQ_APPICON_FRACTION:-0.86}"
    for s in 16 32 64 128 256 512 1024; do
        sips -z $s $s "$IT/appicon-1024.png" --out "$IT/$s.png" -s format png >/dev/null
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

# ── Info.plist ──
# 品牌:应用名 SlowQ,中文名 慢Q(通过 InfoPlist.strings 按系统语言本地化显示)
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>SlowQ</string>
    <key>CFBundleDisplayName</key><string>SlowQ</string>
    <key>CFBundleIdentifier</key><string>com.slowq.app</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>SlowQ</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
    <key>CFBundleLocalizations</key>
    <array><string>zh-Hans</string><string>en</string></array>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>LSUIElement</key><true/>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHumanReadableCopyright</key><string>Copyright 2026 PandaBoby — Apache License 2.0</string>
</dict>
</plist>
PLIST

# ── 本地化显示名 ──
# 中文系统:显示「慢Q」;英文系统:显示 SlowQ。Finder/启动台/辅助功能列表都读这个。
mkdir -p "$APP/Contents/Resources/zh-Hans.lproj" "$APP/Contents/Resources/en.lproj"
cat > "$APP/Contents/Resources/zh-Hans.lproj/InfoPlist.strings" <<'ZH'
"CFBundleName" = "慢Q";
"CFBundleDisplayName" = "慢Q";
ZH
cat > "$APP/Contents/Resources/en.lproj/InfoPlist.strings" <<'EN'
"CFBundleName" = "SlowQ";
"CFBundleDisplayName" = "SlowQ";
EN

# ── 签名 ──
# adhoc 签名(本机无开发者证书)。注意:重新构建后二进制变化可能使辅助功能授权失效,
# 若失效请运行 tccutil reset Accessibility com.slowq.app 后重新勾选。
codesign -s - --force --identifier com.slowq.app "$APP"

echo "✅ 已生成 $APP (v$VERSION, $(lipo -archs "$APP/Contents/MacOS/SlowQ" 2>/dev/null || echo '?'))"
