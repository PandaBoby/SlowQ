# SlowQ v1.0.2

> 菜单栏图标改为全自动、新增 0.5 秒长按档位、修复 App 图标被拉伸。·
> Auto menu bar icon, a 0.5s hold option, and an App icon no longer stretched.

---

## 🐛 修复

### App 图标被纵向拉伸

源图 `SlowQ.png` 是**横版 384×256**(宽高比 1.50),而 macOS 的 App 图标画布必须是正方形。构建脚本原先用 `sips -z N N` 直接缩放,等于把横版图强行压成正方形 —— 图形被纵向撑高变形。

新增 `tools/gen-appicon.swift`:先裁到内容包围盒,再**按原始宽高比**等比放入 1024×1024 正方形画布并居中留白(图形最长边占画布 86%,接近 macOS 图标安全区),最后才缩放成各尺寸。

修复前后对比(实测 icns 位图):

| | 内容宽高比 |
|---|---|
| v1.0.1 | 1.00 ✗(被拉伸) |
| v1.0.2 | 1.49–1.50 ✓(与源图一致) |

## ✨ 改进

### 菜单栏图标:移除手动切换,始终自动

v1.0.1 在菜单里提供「自动 / 单色 / 彩色」三态切换,但实际选择对大多数人是多余的 —— 自动识别已经能正确处理。本版**移除该菜单项**,行为固定为自动:

- 单色图标(如纯黑剪影)→ 模板模式,系统按菜单栏明暗渲染(深色→白、浅色→黑)
- 有真实彩色 → 保留原色

需要强制指定时可继续用隐藏开关:

```bash
defaults write com.slowq.app statusIconTemplate -bool true   # 强制单色
defaults write com.slowq.app statusIconTemplate -bool false  # 强制彩色
defaults delete com.slowq.app statusIconTemplate             # 回到自动
```

### 长按档位新增 0.5 秒

菜单「按住时长」现在提供 **0.5 / 1 / 2 / 3 / 5 秒**。0.5 秒适合已经习惯长按、只想防「手滑一碰」的场景。

---

## 📥 下载 / Download

| 文件 | 说明 |
|---|---|
| `SlowQ-1.0.2-macos-universal.dmg` | 推荐。打开后把 SlowQ 拖进 Applications |
| `SlowQ-1.0.2-macos-universal.zip` | 解压后把 `SlowQ.app` 拖进 Applications |

**通用二进制**,macOS 13 Ventura 及以上,支持 Apple Silicon 与 Intel Mac。

## ⚠️ 首次打开必读

本应用**未经 Apple 开发者签名与公证**,macOS 会拦截首次启动。执行一次:

```bash
xattr -dr com.apple.quarantine /Applications/SlowQ.app
```

或在 Finder 里**右键** `SlowQ.app` → **打开** → 弹窗里再点 **打开**。

## 🔑 授予辅助功能权限

**系统设置 → 隐私与安全性 → 辅助功能 → 勾选 SlowQ**。未授权时菜单栏图标仍会显示,菜单里也提供了直接跳转设置的入口(`⚠️ 打开辅助功能设置`)。授权后自动生效,无需重启。

> **升级提示**:覆盖安装后辅助功能授权可能失效(adhoc 签名随二进制变化)。若拦截不工作,执行 `tccutil reset Accessibility com.slowq.app` 后重新勾选。

---

## English

### Fixed — App icon was stretched vertically

The source artwork is **landscape 384×256** (aspect 1.50) but a macOS app icon canvas must be square. The build script used `sips -z N N`, which squashed the artwork into a square and stretched it vertically.

The new `tools/gen-appicon.swift` crops to the content bounds, then fits the artwork into a 1024×1024 canvas **at its original aspect ratio**, centered with margin (longest edge at 86% of the canvas), and only then scales down to each icon size.

| | Content aspect ratio |
|---|---|
| v1.0.1 | 1.00 ✗ (stretched) |
| v1.0.2 | 1.49–1.50 ✓ (matches source) |

### Changed — menu bar icon is now always automatic

v1.0.1 exposed an Auto/Mono/Color cycle in the menu, but the choice is redundant for most people. This release **removes that menu item**; behavior is fixed to auto-detection: monochrome artwork becomes a template image (rendered white on dark menu bars, black on light ones), colored artwork keeps its colors.

A hidden override remains available via `defaults write com.slowq.app statusIconTemplate -bool true|false` (delete the key to return to auto).

### Added — 0.5-second hold option

The hold duration menu now offers **0.5 / 1 / 2 / 3 / 5 seconds**. The 0.5s setting suits users who are already used to holding and only want protection against a single accidental tap.

Download the `.dmg` or `.zip` below (universal binary, macOS 13+). Clear the quarantine flag once, then grant Accessibility permission in System Settings → Privacy & Security → Accessibility. After upgrading over an older build the grant may need re-applying — use the menu entry, or `tccutil reset Accessibility com.slowq.app` and re-tick.
