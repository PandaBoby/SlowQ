#!/bin/bash
# make-dmg.sh — 制作带自定义安装界面的 DMG
#
# 用法: tools/make-dmg.sh <app路径> <输出dmg> [卷名] [logo路径]
#
# 流程:
#   1. 暂存目录:app + Applications 软链接 + .background/(背景图)+ .VolumeIcon.icns
#   2. hdiutil 生成可读写 UDRW 临时镜像
#   3. 挂载后用 AppleScript 设置 Finder 视图:窗口尺寸、图标大小/坐标、背景图、隐藏工具栏
#   4. 卸载并转换为压缩只读 UDZO
#
# 背景布局与 tools/gen-dmgbackground.swift 中的坐标一一对应,改动时需同步:
#   窗口内容区 680x520,app 图标中心 (175,260)、Applications 中心 (505,260)
set -e

APP_PATH="${1:?用法: make-dmg.sh <app路径> <输出dmg> [卷名] [logo路径]}"
OUT_DMG="${2:?缺少输出 dmg 路径}"
VOLNAME="${3:-SlowQ}"
LOGO="${4:-}"

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WIN_W=680
WIN_H=520
APP_NAME="$(basename "$APP_PATH")"

[ -d "$APP_PATH" ] || { echo "❌ 找不到 app: $APP_PATH"; exit 1; }
[ -n "$LOGO" ] || LOGO="$REPO_DIR/SlowQ/SlowQ.png"

STAGE=$(mktemp -d)
TMP_DMG=$(mktemp -u).dmg
MOUNT_POINT=""

cleanup() {
    if [ -n "$MOUNT_POINT" ] && [ -d "$MOUNT_POINT" ]; then
        hdiutil detach "$MOUNT_POINT" -quiet -force 2>/dev/null || true
    fi
    rm -rf "$STAGE" "$TMP_DMG" 2>/dev/null || true
}
trap cleanup EXIT

# ── 1. 暂存目录 ──
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# 背景图(直接输出 2x 像素:实测 Finder 会等比缩放到窗口,1x 图在 Retina 上会发虚)
mkdir -p "$STAGE/.background"
swift "$REPO_DIR/tools/gen-dmgbackground.swift" "$STAGE/.background" "$WIN_W" "$WIN_H" "$LOGO"

# 卷图标(已挂载的磁盘在 Finder 里显示蜗牛)
APP_ICNS="$APP_PATH/Contents/Resources/AppIcon.icns"
if [ -f "$APP_ICNS" ]; then
    cp "$APP_ICNS" "$STAGE/.VolumeIcon.icns"
fi

# ── 2. 可读写临时镜像 ──
hdiutil create -srcfolder "$STAGE" -volname "$VOLNAME" -fs HFS+ -format UDRW -quiet "$TMP_DMG"

# ── 3. 挂载并设置视图 ──
MOUNT_POINT=$(hdiutil attach "$TMP_DMG" -readwrite -noverify -noautoopen 2>/dev/null \
    | grep -o '/Volumes/.*' | head -1)
[ -n "$MOUNT_POINT" ] || { echo "❌ 挂载失败"; exit 1; }

# Finder 需要一点时间识别新卷
sleep 2

osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        -- bounds 含标题栏,内容区高度 = 总高 - 28
        set the bounds of container window to {220, 140, 220 + $WIN_W, 140 + $WIN_H + 28}
        set v to the icon view options of container window
        set arrangement of v to not arranged
        set icon size of v to 128
        set position of item "$APP_NAME" of container window to {175, 260}
        set position of item "Applications" of container window to {505, 260}
        try
            set background picture of v to file ".background:background.png"
        on error errMsg number errNum
            log "⚠️  背景图设置失败: " & errMsg & " (" & errNum & ")"
        end try
        update without registering applications
        delay 2
    end tell
end tell
APPLESCRIPT

# 卷自定义图标标志(需在卸载前设置)
if [ -f "$MOUNT_POINT/.VolumeIcon.icns" ]; then
    SetFile -a C "$MOUNT_POINT" 2>/dev/null || true
fi

# ── 卸载:必须交给 Finder eject ──
# 关键经验:直接 `hdiutil detach` 会丢掉刚设置的视图 —— Finder 在卸载时
# 会用它内存里的旧快照覆盖 .DS_Store,背景图别名与图标大小随之丢失。
# 让 Finder 自己退盘,它才会先把新状态刷进 .DS_Store。
sleep 2
osascript -e "tell application \"Finder\" to eject disk \"$VOLNAME\"" >/dev/null 2>&1 || true
for _ in $(seq 1 10); do
    mount | grep -q "on $MOUNT_POINT" || break
    sleep 1
done
if mount | grep -q "on $MOUNT_POINT"; then
    echo "⚠️  Finder 退盘超时,回退强制卸载(视图设置可能丢失)"
    hdiutil detach "$MOUNT_POINT" -force -quiet 2>/dev/null || true
fi
MOUNT_POINT=""

# ── 4. 转成压缩只读镜像 ──
mkdir -p "$(dirname "$OUT_DMG")"
rm -f "$OUT_DMG"
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUT_DMG" -quiet

echo "💿 $(basename "$OUT_DMG")"
