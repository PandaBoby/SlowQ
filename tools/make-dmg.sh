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
    rm -rf "$STAGE" "$TMP_DMG" "${VOL_TMP:-}" 2>/dev/null || true
}
trap cleanup EXIT

# ── 0. 预清理:卸载同名残留卷 ──
# 若存在 "/Volumes/SlowQ 1" 这类残留,Finder 里会出现两个同名磁盘,
# AppleScript 的 `disk "SlowQ"` 无法定位,eject 会静默失败。
while IFS= read -r mp; do
    [ -n "$mp" ] && hdiutil detach "$mp" -force -quiet 2>/dev/null || true
done < <(mount | grep -i " on /Volumes/${VOLNAME}" | sed 's/.* on \(.*\) (.*/\1/')

# ── 1. 暂存目录 ──
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# 背景图(直接输出 2x 像素:实测 Finder 会等比缩放到窗口,1x 图在 Retina 上会发虚)
mkdir -p "$STAGE/.background"
swift "$REPO_DIR/tools/gen-dmgbackground.swift" "$STAGE/.background" "$WIN_W" "$WIN_H" "$LOGO"

# 卷图标:自绘的磁盘造型(圆角机身 + 接缝 + 指示灯 + 白色 logo),
# 比直接用 App 图标更像一个"安装盘",风格与背景横幅统一。
#
# ⚠️ 关键:必须先只在临时目录生成 icns,**稍后写入已挂载的卷**。
# 实测:若在 hdiutil create 之前把 .VolumeIcon.icns 放进暂存目录,
# Finder 打开卷设置视图时会把它删掉,最终镜像里就没有卷图标了。
VOL_TMP=$(mktemp -d)
VOL_ICNS="$VOL_TMP/VolumeIcon.icns"
if swift "$REPO_DIR/tools/gen-volumeicon.swift" "$VOL_TMP/vol-1024.png" 1024 "$LOGO"; then
    VOLSET="$VOL_TMP/VolumeIcon.iconset"
    mkdir -p "$VOLSET"
    for s in 16 32 64 128 256 512 1024; do
        sips -z $s $s "$VOL_TMP/vol-1024.png" --out "$VOL_TMP/v$s.png" -s format png >/dev/null
    done
    cp "$VOL_TMP/v16.png"   "$VOLSET/icon_16x16.png"
    cp "$VOL_TMP/v32.png"   "$VOLSET/icon_16x16@2x.png"
    cp "$VOL_TMP/v32.png"   "$VOLSET/icon_32x32.png"
    cp "$VOL_TMP/v64.png"   "$VOLSET/icon_32x32@2x.png"
    cp "$VOL_TMP/v128.png"  "$VOLSET/icon_128x128.png"
    cp "$VOL_TMP/v256.png"  "$VOLSET/icon_128x128@2x.png"
    cp "$VOL_TMP/v256.png"  "$VOLSET/icon_256x256.png"
    cp "$VOL_TMP/v512.png"  "$VOLSET/icon_256x256@2x.png"
    cp "$VOL_TMP/v512.png"  "$VOLSET/icon_512x512.png"
    cp "$VOL_TMP/v1024.png" "$VOLSET/icon_512x512@2x.png"
    iconutil -c icns "$VOLSET" -o "$VOL_ICNS"
    echo "   ✓ 卷图标已生成(待写入镜像)"
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

# ── 写入卷图标 ──
# 必须在 Finder 设置视图之后:Finder 打开卷时会把暂存阶段带进来的
# .VolumeIcon.icns 删掉,所以这里在挂载的卷上现写。
if [ -f "$VOL_ICNS" ]; then
    cp "$VOL_ICNS" "$MOUNT_POINT/.VolumeIcon.icns"
    SetFile -a C "$MOUNT_POINT" 2>/dev/null || true
    # 必须 sync:否则文件还在页缓存里就退盘,镜像里会丢
    sync
    sleep 1
    if [ -f "$MOUNT_POINT/.VolumeIcon.icns" ]; then
        echo "   ✓ 卷图标已写入镜像"
    else
        echo "   ⚠️  卷图标写入失败"
    fi
fi

# ── 卸载:必须交给 Finder eject ──
# 关键经验:直接 `hdiutil detach` 会丢掉刚设置的视图 —— Finder 在卸载时
# 会用它内存里的旧快照覆盖 .DS_Store,背景图别名与图标大小随之丢失。
# 让 Finder 自己退盘,它才会先把新状态刷进 .DS_Store。
sleep 2
osascript -e "tell application \"Finder\" to eject disk \"$VOLNAME\"" >/dev/null 2>&1 || true
for _ in $(seq 1 25); do
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
