# SlowQ v1.0.5 · 慢Q

> 自定义磁盘卷图标:挂载 DMG 后,桌面与 Finder 里显示一枚专属安装盘图标。
> Custom volume icon for the disk image.

---

## ✨ 本次改动

### 自绘的卷图标

之前挂载 DMG 后显示的是系统通用磁盘图标(或直接套用 App 图标)。现在改为**专门绘制的安装盘造型**:

- 圆角金属机身 + 顶部高光渐变
- 底部接缝分色,带一枚绿色电源指示灯(含光晕)
- 机身中央是**白色蜗牛 logo**(深色底上清晰可辨)
- 配色与安装界面横幅一致,整条安装体验视觉统一

由 `tools/gen-volumeicon.swift` 用代码绘制,无外部设计资源;输出 1024px 底图后经 `sips` + `iconutil` 生成 `.VolumeIcon.icns`。

> 应用本身与 v1.0.4 **完全一致**,本版只更新安装盘外观。

## 🐛 顺带修掉的两个打包坑

这两个问题都只有实际制作镜像时才会暴露,已在新脚本里绕开并写进注释:

**1. Finder 会删掉 `.VolumeIcon.icns`**

若在 `hdiutil create` 之前把卷图标放进暂存目录,Finder 打开该卷设置视图时会把它删除,最终镜像里就没有卷图标了。改为**先只在临时目录生成 icns,等 Finder 设置完视图后再写入已挂载的卷**。

**2. 残留同名卷会让退盘静默失败**

制作过程中若留下 `/Volumes/SlowQ 1` 这类残留挂载,Finder 里会出现两个同名磁盘,`eject disk "SlowQ"` 无法定位、静默失败,进而回退到强制卸载 —— 而强制卸载会丢失刚设置好的视图。现在脚本在开始前会**预清理同名残留卷**,并在写入卷图标后 `sync` 强制落盘。

> 顺带说明为什么卸载必须交给 Finder:直接 `hdiutil detach` 时 Finder 会用内存里的旧快照覆盖 `.DS_Store`(实测字节数从 10244 掉回 6148,背景图与图标大小全丢),只有 Finder 自己退盘才会先刷盘。

---

## 📥 下载 / Download

| 文件 | 说明 |
|---|---|
| `SlowQ-1.0.5-macos-universal.dmg` | 推荐。打开后把 SlowQ(慢Q)拖进 Applications |
| `SlowQ-1.0.5-macos-universal.zip` | 解压后拖进 Applications |

**通用二进制**,macOS 13 Ventura 及以上,支持 Apple Silicon 与 Intel Mac。

## ⚠️ 首次打开必读

本应用**未经 Apple 开发者签名与公证**,macOS 会拦截首次启动。执行一次:

```bash
xattr -dr com.apple.quarantine /Applications/SlowQ.app
```

或在 Finder 里**右键** → **打开** → 弹窗里再点 **打开**。

## 🔑 授予辅助功能权限

**系统设置 → 隐私与安全性 → 辅助功能 → 勾选「慢Q」**。未授权时菜单栏图标仍会显示,菜单里也提供了直接跳转设置的入口。

> **升级提示**:覆盖安装后辅助功能授权可能失效(adhoc 签名随二进制变化)。若拦截不工作,执行 `tccutil reset Accessibility com.slowq.app` 后重新勾选。

---

## English

### Custom volume icon

Mounting the disk image now shows a purpose-drawn installer-disk icon instead of the generic system volume icon:

- Rounded metallic body with a top gloss gradient
- A seam near the bottom with a green power LED (with glow)
- The snail logo rendered **white** in the centre so it reads clearly on the dark body
- Colours matched to the installer banner for a consistent experience

Drawn entirely in code by `tools/gen-volumeicon.swift`; a 1024px master is converted to `.VolumeIcon.icns` via `sips` + `iconutil`.

> The app itself is **identical to v1.0.4** — this release only changes how the disk image looks.

### Two packaging bugs fixed along the way

**1. Finder deletes `.VolumeIcon.icns`** — if the icon is placed in the staging folder before `hdiutil create`, Finder removes it when it opens the volume to apply the view settings, so the final image ends up with no volume icon. The script now generates the icns in a temp directory and copies it onto the mounted volume *after* Finder has done its work.

**2. A stale same-named volume makes ejecting fail silently** — a leftover mount such as `/Volumes/SlowQ 1` makes Finder see two disks with the same name, so `eject disk "SlowQ"` cannot resolve and fails without an error, which falls back to a forced detach that discards the view settings. The script now pre-cleans stale mounts and runs `sync` after writing the icon.

> Reminder on why the volume must be ejected by Finder: a plain `hdiutil detach` lets Finder overwrite `.DS_Store` with its stale in-memory snapshot (measured: 10244 bytes back down to 6148, losing the background and icon size). Only Finder's own eject flushes first.

Download the `.dmg` or `.zip` below (universal binary, macOS 13+). Clear the quarantine flag once, then grant Accessibility permission. After upgrading over an older build the grant may need re-applying via `tccutil reset Accessibility com.slowq.app`.
