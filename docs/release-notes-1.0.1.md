# SlowQ v1.0.1

> 修复深色菜单栏下图标隐形的问题。· Fixes the invisible menu bar icon on dark menu bars.

---

## 🐛 修复

### 菜单栏图标在深色菜单栏下隐形

v1.0.0 使用彩色模式渲染菜单栏图标,而当前图标是**纯黑剪影**(`rgb(0,0,0)` + 透明背景)。深色菜单栏(深色外观,或浅色外观配深色壁纸)下,黑图标配黑背景就看不见了。

v1.0.1 改为**自动识别**:

- 加载图标时采样像素,若所有不透明像素的 RGB 三通道差异都很小(阈值 0.12),判定为**单色**
- 单色图标 → 自动使用**模板模式**,由系统按菜单栏明暗渲染(深色→白色、浅色→黑色)
- 有真实彩色信息 → 保持彩色模式,不损失配色

菜单项也从「彩色 / 单色」两态改为**三态循环**,保留手动控制:

```
菜单栏图标:自动 · 单色   →   单色(手动)   →   彩色(手动)   →   自动 · 单色
```

> **自动**是默认值。若你之前手动设过彩色,升级后请点菜单切回「自动」(或在终端执行 `defaults delete com.slowq.app statusIconTemplate`)。

### 未授权时菜单栏不显示图标

v1.0.0 只在拿到辅助功能授权后才创建状态栏项,导致首次安装、还没授权时菜单栏完全没有 SlowQ 的痕迹,容易被误认为「应用没启动」。

v1.0.1 改为**启动即显示菜单栏图标**,无论是否已授权。

### 新增授权入口

未授权时,菜单里会多出一项:

```
⚠️ 打开辅助功能设置(需授权后才能拦截 ⌘Q)
```

点击直接跳到系统设置的辅助功能面板,省去手动翻找。

---

## 📥 下载 / Download

| 文件 | 说明 |
|---|---|
| `SlowQ-1.0.1-macos-universal.dmg` | 推荐。打开后把 SlowQ 拖进 Applications |
| `SlowQ-1.0.1-macos-universal.zip` | 解压后把 `SlowQ.app` 拖进 Applications |

**通用二进制**,macOS 13 Ventura 及以上,支持 Apple Silicon 与 Intel Mac。

## ⚠️ 首次打开必读

本应用**未经 Apple 开发者签名与公证**,macOS 会拦截首次启动。执行一次:

```bash
xattr -dr com.apple.quarantine /Applications/SlowQ.app
```

或在 Finder 里**右键** `SlowQ.app` → **打开** → 弹窗里再点 **打开**。

## 🔑 授予辅助功能权限

**系统设置 → 隐私与安全性 → 辅助功能 → 勾选 SlowQ**。未授权时 SlowQ 无法拦截 ⌘Q,但菜单栏图标仍会显示,菜单里也提供了直接跳转设置的入口。授权后无需重启,SlowQ 会自动检测并立即生效。

> **升级提示**:从旧版覆盖安装后,辅助功能授权可能失效(adhoc 签名随二进制变化)。若菜单里出现 `⚠️ 打开辅助功能设置`,点击它重新勾选即可;若开关看着是开着的但仍无效,执行:
> ```bash
> tccutil reset Accessibility com.slowq.app
> ```
> 然后重新打开 SlowQ 并重新勾选。

---

## English

**Fixes the invisible menu bar icon on dark menu bars.** v1.0.0 rendered the icon in color mode, but the artwork is a pure black silhouette — invisible against a dark menu bar (dark appearance, or light appearance with a dark wallpaper).

v1.0.1 **auto-detects** the artwork: if every opaque pixel is effectively monochrome (RGB channel spread < 0.12) the icon is used as a **template image**, so macOS renders it white on dark menu bars and black on light ones. Genuinely colored artwork still renders in full color.

The menu toggle is now a three-state cycle, keeping manual control: `Auto · Mono → Mono (manual) → Color (manual) → Auto · Mono`.

Also fixed:

- **No menu bar icon before accessibility is granted** — the status item is now created at launch regardless of permission, so you can always see that SlowQ is running.
- **New menu entry** `⚠️ 打开辅助功能设置` (shown only when not yet trusted) that jumps straight to the Accessibility pane.

Download the `.dmg` or `.zip` below (universal binary, macOS 13+). Clear the quarantine flag once before first launch:

```bash
xattr -dr com.apple.quarantine /Applications/SlowQ.app
```

Then grant Accessibility permission in System Settings → Privacy & Security → Accessibility. After upgrading over an older build the grant may need to be re-applied (the ad-hoc signature changes with the binary); use the new menu entry, or `tccutil reset Accessibility com.slowq.app` and re-tick.
