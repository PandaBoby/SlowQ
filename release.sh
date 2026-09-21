#!/bin/bash
# SlowQ 发布脚本:构建通用二进制 → 打包 zip/dmg → (可选)发布 GitHub Release
#
# 用法:
#   ./release.sh                 # 只构建并打包到 dist/
#   ./release.sh --publish       # 构建、打包并发布 GitHub Release
#   VERSION=1.1.0 ./release.sh   # 指定版本号
set -e
cd "$(dirname "$0")"

VERSION="${VERSION:-1.0.0}"
TAG="v$VERSION"
DIST="dist"

echo "=== 构建 SlowQ $TAG ==="
SLOWQ_VERSION="$VERSION" ./build-app.sh

APP="SlowQ/.build-app/SlowQ.app"
[ -d "$APP" ] || { echo "❌ 未找到 $APP"; exit 1; }

mkdir -p "$DIST"
rm -f "$DIST"/*.zip "$DIST"/*.dmg

# ── ZIP:ditto 保留资源分支与权限(.app 打包的正确方式)──
ZIP="$DIST/SlowQ-$VERSION-macos-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
echo "📦 $ZIP"

# ── DMG:内含 app + Applications 软链接,拖拽安装 ──
DMG="$DIST/SlowQ-$VERSION-macos-universal.dmg"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "SlowQ" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGE"
echo "💿 $DMG"

echo
echo "=== 产物 ==="
ls -lh "$DIST"

if [ "${1:-}" = "--publish" ]; then
    echo
    echo "=== 发布 GitHub Release $TAG ==="
    if gh release view "$TAG" >/dev/null 2>&1; then
        echo "Release $TAG 已存在,改为上传/覆盖资源"
        gh release upload "$TAG" "$ZIP" "$DMG" --clobber
    else
        gh release create "$TAG" "$ZIP" "$DMG" \
            --title "SlowQ $TAG" \
            --notes-file "docs/release-notes-$VERSION.md"
        echo "✅ 已发布:https://github.com/PandaBoby/SlowQ/releases/tag/$TAG"
    fi
fi
