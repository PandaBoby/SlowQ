# SlowQ v1.0.4 · 慢Q

> 品牌强化:新增中文名「慢Q」、副标题与中英 Slogan。
> Branding update: Chinese name 慢Q, subtitle and bilingual slogans.

---

## 🏷 命名

| 项 | 内容 |
|---|---|
| 应用名 | **SlowQ** |
| 中文名 | **慢Q** |
| 中文副标题 | 防误触退出助手 |
| App Store 标题 | 慢Q - 防误触退出 |
| GitHub 描述 | SlowQ(慢Q)—— 防止误触 Command+Q 退出的 macOS 菜单栏工具 |
| 中文 Slogan | **退一步,再确认。** |
| 英文 Slogan | **Slow down quitting.** |

## ✨ 本次改动

**应用内**

- 中文系统下应用名显示为 **慢Q**,英文系统显示 **SlowQ** —— 通过 `InfoPlist.strings` 按系统语言本地化
- 菜单里的退出项改为「退出 慢Q (⌥⌘Q)」
- 补充 `LSApplicationCategoryType`(工具类),为后续上架做准备
- 新增 `CFBundleLocalizations`,声明支持简体中文与英文

> ⚠️ **注意**:本地化后,**Finder 图标名与「系统设置 → 辅助功能」列表里显示的是「慢Q」**。授权时请在列表中找「慢Q」(英文系统为 SlowQ)。

**安装界面**

顶部横幅改为完整的品牌区:

```
🐌  SlowQ  慢Q
    防误触退出助手 · 退一步，再确认。
    Slow down quitting.
```

**仓库与文档**

- GitHub / Gitee 仓库描述统一为:SlowQ(慢Q)—— 防止误触 Command+Q 退出的 macOS 菜单栏工具
- 中英 README 的标题区加入中文名、副标题与 Slogan
- 新增「命名与品牌」对照表,便于上架 App Store 时复用

---

## 📥 下载 / Download

| 文件 | 说明 |
|---|---|
| `SlowQ-1.0.4-macos-universal.dmg` | 推荐。打开后把 SlowQ(慢Q)拖进 Applications |
| `SlowQ-1.0.4-macos-universal.zip` | 解压后拖进 Applications |

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

### Naming

| Item | Value |
|---|---|
| App name | **SlowQ** |
| Chinese name | **慢Q** |
| Chinese subtitle | 防误触退出助手 |
| App Store title | 慢Q - 防误触退出 |
| GitHub description | SlowQ(慢Q)—— 防止误触 Command+Q 退出的 macOS 菜单栏工具 |
| Chinese slogan | **退一步,再确认。** |
| English slogan | **Slow down quitting.** |

### What changed

- The app now displays as **慢Q** on Chinese-locale systems and **SlowQ** on English ones, localized via `InfoPlist.strings`.
- The Quit menu item reads `退出 慢Q (⌥⌘Q)`.
- Added `LSApplicationCategoryType` (Utilities) and `CFBundleLocalizations`.
- **Note:** because of the localization, the Finder icon label and the Accessibility permission entry read **慢Q** on Chinese systems — look for 慢Q when granting permission (English systems show SlowQ).
- The installer banner now shows the full brand block: `SlowQ 慢Q` / `防误触退出助手 · 退一步，再确认。` / `Slow down quitting.`
- Repository descriptions on GitHub and Gitee updated; both READMEs gained the Chinese name, subtitle, slogans and a naming reference table.

Download the `.dmg` or `.zip` below (universal binary, macOS 13+). Clear the quarantine flag once, then grant Accessibility permission. After upgrading over an older build the grant may need re-applying via `tccutil reset Accessibility com.slowq.app`.
