# SlowQ v1.0.8 · 慢Q

> 提示条移到屏幕顶部并严格居中。
> Toast moved to the top of the screen and always centred.

---

## ✨ 调整

### 提示条位置:屏幕中央 → **屏幕顶部居中**

之前「图标已隐藏 / 已恢复」的提示条出现在屏幕中间偏下的位置。现在改为:

- **位置固定在屏幕顶部** —— 菜单栏正下方 10pt,视觉上属于"系统通知"区域,不遮挡内容
- **严格水平居中** —— 对齐 `visibleFrame` 的中心(而非整个屏幕,避免多显示器/刘海屏偏移)
- **宽度自适应内容** —— 卡片宽度按文字实际宽度计算并夹在 240–680pt 之间,短提示不会被撑成大块,长提示也不会被截断;**任何宽度都保持居中**
- **胶囊形圆角** —— 圆角半径取高度一半,顶部提示看起来更轻盈

实测两种长度的提示条(由应用自身打印坐标验证):

| 提示内容 | 宽度 | 位置 | 居中 | 距顶部 |
|---|---|---|---|---|
| 菜单栏图标已隐藏 · 再次打开 慢Q 即可恢复 | 314pt | x=707 | ✓ | 43pt |
| 菜单栏图标已恢复 | 240pt | x=744 | ✓ | 43pt |

两者中心都落在 864pt(= 屏幕中心),宽度不同但都严格居中。

---

## 📥 下载 / Download

| 文件 | 说明 |
|---|---|
| `SlowQ-1.0.8-macos-universal.dmg` | 推荐。打开后把 SlowQ(慢Q)拖进 Applications |
| `SlowQ-1.0.8-macos-universal.zip` | 解压后拖进 Applications |

**通用二进制**,macOS 13 Ventura 及以上,支持 Apple Silicon 与 Intel Mac。

## ⚠️ 首次打开必读

本应用**未经 Apple 开发者签名与公证**,macOS 会拦截首次启动。执行一次:

```bash
xattr -dr com.apple.quarantine /Applications/SlowQ.app
```

## 🔑 授予辅助功能权限

**系统设置 → 隐私与安全性 → 辅助功能 → 勾选「慢Q」**。

> **升级提示**:覆盖安装后辅助功能授权可能失效(adhoc 签名随二进制变化)。若拦截不工作,执行 `tccutil reset Accessibility com.slowq.app` 后重新勾选。

---

## English

### Toast relocated: centre of screen → **top centre**

The "icon hidden / icon restored" toast used to appear slightly below the middle of the screen. Now:

- **Pinned to the top of the screen** — 10 pt below the menu bar, where users expect system notifications, so it never covers content
- **Strictly horizontally centred** — aligned to `visibleFrame`'s centre rather than the full screen, so notched and multi-display setups stay correct
- **Width adapts to the text** — clamped to 240–680 pt, so short messages don't become huge blocks and long ones aren't truncated; **every width stays centred**
- **Capsule corners** — radius is half the height, which reads lighter for a top-of-screen toast

Measured with the app logging its own frame:

| Message | Width | x | Centred | From top |
|---|---|---|---|---|
| menu bar icon hidden · open 慢Q again to restore | 314 pt | 707 | ✓ | 43 pt |
| menu bar icon restored | 240 pt | 744 | ✓ | 43 pt |

Both centres land on 864 pt (the screen centre) — different widths, both strictly centred.

Download the `.dmg` or `.zip` below (universal binary, macOS 13+). Clear the quarantine flag once, then grant Accessibility permission.
