#!/bin/bash
# SlowQ 发布脚本:构建通用二进制 → 打包 zip/dmg → (可选)发布 GitHub / Gitee Release
#
# 用法:
#   ./release.sh                    # 只构建并打包到 dist/
#   ./release.sh --publish          # 同时发布 GitHub Release
#   ./release.sh --gitee            # 同时发布 Gitee Release
#   ./release.sh --publish --gitee  # 两边都发
#   VERSION=1.1.0 ./release.sh      # 指定版本号
#
# Gitee 需要私人令牌(勾选 projects 权限),默认从 ~/.token/gitee-token 读取,
# 可用 GITEE_TOKEN_FILE 环境变量改路径,或用 GITEE_TOKEN 直接传入。
# 令牌只用于 API 调用,不会打印到输出里。
set -e
cd "$(dirname "$0")"

VERSION="${VERSION:-1.0.0}"
TAG="v$VERSION"
DIST="dist"
NOTES="docs/release-notes-$VERSION.md"
GITEE_REPO="${GITEE_REPO:-pandaboby/SlowQ}"

PUBLISH_GITHUB=0
PUBLISH_GITEE=0
for arg in "$@"; do
    case "$arg" in
        --publish) PUBLISH_GITHUB=1 ;;
        --gitee)   PUBLISH_GITEE=1 ;;
        *) echo "未知参数: $arg"; exit 1 ;;
    esac
done

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

# ─────────────────────────── GitHub ───────────────────────────
if [ "$PUBLISH_GITHUB" = "1" ]; then
    echo
    echo "=== 发布 GitHub Release $TAG ==="
    if gh release view "$TAG" >/dev/null 2>&1; then
        echo "Release $TAG 已存在,改为上传/覆盖资源"
        gh release upload "$TAG" "$ZIP" "$DMG" --clobber
    else
        gh release create "$TAG" "$ZIP" "$DMG" \
            --title "SlowQ $TAG" \
            --notes-file "$NOTES"
        echo "✅ GitHub:https://github.com/PandaBoby/SlowQ/releases/tag/$TAG"
    fi
fi

# ─────────────────────────── Gitee ───────────────────────────
if [ "$PUBLISH_GITEE" = "1" ]; then
    echo
    echo "=== 发布 Gitee Release $TAG ==="

    TOKEN="${GITEE_TOKEN:-}"
    if [ -z "$TOKEN" ]; then
        TOKEN_FILE="${GITEE_TOKEN_FILE:-$HOME/.token/gitee-token}"
        [ -f "$TOKEN_FILE" ] || { echo "❌ 未找到令牌文件: $TOKEN_FILE"; exit 1; }
        TOKEN=$(tr -d '\n\r ' < "$TOKEN_FILE")
    fi
    [ -n "$TOKEN" ] || { echo "❌ Gitee 令牌为空"; exit 1; }
    [ -f "$NOTES" ] || { echo "❌ 未找到发布说明: $NOTES"; exit 1; }

    API="https://gitee.com/api/v5/repos/$GITEE_REPO"

    # 确保 tag 已存在于 Gitee —— Release 依赖 tag,缺失时 API 会失败
    if git remote get-url gitee >/dev/null 2>&1; then
        if ! git ls-remote --tags gitee "refs/tags/$TAG" 2>/dev/null | grep -q "refs/tags/$TAG"; then
            git tag -f "$TAG" HEAD >/dev/null 2>&1 || true
            echo "→ 推送 tag $TAG 到 Gitee"
            git push gitee "$TAG" >/dev/null 2>&1 && echo "  ✓ tag 已推送" \
                || echo "  ⚠️  tag 推送失败,请确认 gitee remote 与凭据"
        fi
    else
        echo "⚠️  未配置 gitee remote,跳过 tag 推送(若 tag 不存在,Release 可能创建失败)"
    fi

    # 查询同名 tag 是否已有 Release,有则复用其 id(避免重复创建报错)
    RID=$(curl -s "$API/releases?access_token=$TOKEN" | python3 -c "
import json,sys
tag = sys.argv[1]
try:
    for r in json.load(sys.stdin):
        if r.get('tag_name') == tag:
            print(r.get('id')); break
except Exception:
    pass
" "$TAG")

    if [ -z "$RID" ]; then
        RID=$(curl -s -X POST "$API/releases" \
            --data-urlencode "access_token=$TOKEN" \
            --data-urlencode "tag_name=$TAG" \
            --data-urlencode "name=SlowQ $TAG" \
            --data-urlencode "target_commitish=main" \
            --data-urlencode "prerelease=false" \
            --data-urlencode "body=$(cat "$NOTES")" \
            | python3 -c "
import json,sys
d = json.load(sys.stdin)
if 'id' in d: print(d['id'])
else: sys.stderr.write('创建失败: ' + json.dumps(d, ensure_ascii=False)[:300] + '\n')
")
        [ -n "$RID" ] && echo "✓ 已创建 Release (id=$RID)"
    else
        echo "✓ Release 已存在 (id=$RID),更新说明并覆盖附件"
        curl -s -X PATCH "$API/releases/$RID" \
            --data-urlencode "access_token=$TOKEN" \
            --data-urlencode "name=SlowQ $TAG" \
            --data-urlencode "body=$(cat "$NOTES")" >/dev/null
        # 删除同名旧附件,避免重复
        curl -s "$API/releases/$RID/attach_files?access_token=$TOKEN" | python3 -c "
import json,sys,os
for a in json.load(sys.stdin):
    if a.get('name','').startswith('SlowQ-'):
        print(a.get('id'))
" | while read -r AID; do
            [ -n "$AID" ] && curl -s -X DELETE "$API/releases/$RID/attach_files/$AID?access_token=$TOKEN" >/dev/null
        done
    fi

    [ -n "$RID" ] || { echo "❌ 无法创建/定位 Gitee Release"; exit 1; }

    for f in "$ZIP" "$DMG"; do
        RESULT=$(curl -s -X POST "$API/releases/$RID/attach_files" \
            -F "access_token=$TOKEN" -F "file=@$f")
        echo "$RESULT" | python3 -c "
import json,sys
d = json.load(sys.stdin)
print('  ✓ 已上传', d.get('name') if isinstance(d, dict) else d)
" 2>/dev/null || echo "  ✗ 上传失败: $(echo "$RESULT" | head -c 200)"
    done

    echo "✅ Gitee:https://gitee.com/$GITEE_REPO/releases/tag/$TAG"
fi
