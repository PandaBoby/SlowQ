# SlowQ v1.0.3

> 全新的 DMG 安装界面。· A redesigned DMG installer.

---

## ✨ 新的安装界面

打开 DMG 不再是朴素的白底加两个图标,而是一个完整的引导页:

- **顶部品牌横幅** —— 深色渐变底 + 蜗牛 logo + 应用名 + 中英双语一句话说明
- **中间拖拽指引** —— 连接 app 与「应用程序」文件夹的弧形箭头
- **底部双语说明** —— 中文主说明 + 英文对照,并附首次打开被 Gatekeeper 拦截时的终端命令
- **命令行代码框** —— 需要执行的 `xattr` 命令单独放在圆角框里,方便对照输入
- **卷图标** —— 挂载后在 Finder 侧边栏显示蜗牛图标
- **窗口** —— 隐藏工具栏与状态栏,图标 128px,窗口尺寸与背景精确对齐

## 🔍 顺带修掉的一个渲染问题

初版安装界面的背景与文字在 Retina 屏幕上明显发虚。定位过程:

1. 先怀疑字号太小 → 放大字号、提高对比度,**仍然发虚**
2. 测量屏幕捕获的锐度:文字边缘对比度只有源图的一半
3. 关键发现:**Finder 会把背景图等比缩放到窗口大小,并不会按 `background@2x.png` 命名去挑选 2x 图**

所以只提供 1x 图时,它在 Retina 上被放大 2 倍 → 必然发虚。改为**直接输出 2x 像素尺寸的背景图**(1360×520 pt 的设计导出 1360×1040 px),缩放后正好与屏幕像素 1:1 对应。

实测中文说明行的文字边缘对比度(95 分位):

| 方案 | 边缘对比度 |
|---|---|
| 1x 图(被放大 2 倍) | 0.2235 |
| 2x 像素图(1:1 映射) | **0.4627**(约 2 倍) |

同时 DMG 体积反而更小(629 KB → 516 KB),因为不再需要同时塞入两份背景图。

## 📦 其他

- 新增 `tools/make-dmg.sh`:独立的 DMG 制作脚本,处理暂存目录、Finder 视图设置、退盘与压缩
- 新增 `tools/gen-dmgbackground.swift`:安装界面背景生成器(纯代码绘制,无外部设计资源)
- `release.sh` 的 DMG 环节改为调用 `make-dmg.sh`

> **卸载方式的一个坑**:设置 Finder 视图后不能用 `hdiutil detach` 直接卸载 —— Finder 会在卸载时用内存里的旧快照覆盖 `.DS_Store`,背景图与图标大小全部丢失。必须交给 Finder 自己 `eject` 才会先刷盘。这个坑已在新脚本里绕开并注释说明。

---

## 📥 下载 / Download

| 文件 | 说明 |
|---|---|
| `SlowQ-1.0.3-macos-universal.dmg` | 推荐。打开后把 SlowQ 拖进 Applications |
| `SlowQ-1.0.3-macos-universal.zip` | 解压后把 `SlowQ.app` 拖进 Applications |

**应用本身与 v1.0.2 功能完全相同**,本次只改进了安装界面 —— 已经在用 v1.0.2 的话无需重新安装。

**通用二进制**,macOS 13 Ventura 及以上,支持 Apple Silicon 与 Intel Mac。

## ⚠️ 首次打开必读

本应用**未经 Apple 开发者签名与公证**,macOS 会拦截首次启动。执行一次:

```bash
xattr -dr com.apple.quarantine /Applications/SlowQ.app
```

或在 Finder 里**右键** `SlowQ.app` → **打开** → 弹窗里再点 **打开**。

## 🔑 授予辅助功能权限

**系统设置 → 隐私与安全性 → 辅助功能 → 勾选 SlowQ**。未授权时菜单栏图标仍会显示,菜单里也提供了直接跳转设置的入口。

---

## English

### New DMG installer

Opening the disk image now shows a proper guided layout instead of a plain white background: a dark gradient banner with the snail logo, app name and a one-line pitch; a curved drag arrow between the app and the Applications folder; bilingual instructions at the bottom including the terminal command needed if Gatekeeper blocks the first launch; and a custom volume icon.

### Fixed — soft/blurry background on Retina

The first version of the installer looked visibly soft. Enlarging the fonts and raising contrast did **not** help. Measuring the screen capture showed the text edge contrast was only half that of the source image.

Root cause: **Finder scales the background picture to fit the window — it does not look for a `background@2x.png` sibling.** Providing only a 1x image means it gets upscaled 2× on a Retina display. The fix is to ship the background at 2× pixel dimensions (a 680×520 pt design exported at 1360×1040 px), which maps 1:1 to screen pixels after scaling.

Measured 95th-percentile edge contrast for a line of Chinese text:

| Approach | Edge contrast |
|---|---|
| 1x image (upscaled 2×) | 0.2235 |
| 2x-pixel image (1:1) | **0.4627** (≈2×) |

The DMG also got smaller (629 KB → 516 KB) since only one background image is needed now.

### Notes

- New `tools/make-dmg.sh` and `tools/gen-dmgbackground.swift`; `release.sh` now delegates DMG creation.
- Setting up the Finder view means you **cannot** detach with `hdiutil detach` — Finder overwrites `.DS_Store` with its stale in-memory snapshot on unmount, losing the background and icon size. The volume must be ejected by Finder itself so it flushes first. The new script handles this.

**The app itself is functionally identical to v1.0.2** — this release only improves the installer, so existing users need not reinstall. Universal binary, macOS 13+. Clear the quarantine flag once before first launch (`xattr -dr com.apple.quarantine /Applications/SlowQ.app`), then grant Accessibility permission.
