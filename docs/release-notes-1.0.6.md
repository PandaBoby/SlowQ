# SlowQ v1.0.6 · 慢Q

> 一组实用功能:隐藏菜单栏图标、登录时自动启动、定时暂停、关于。
> Practical additions: hide the menu bar icon, launch at login, timed pause, About.

---

## ✨ 新增功能

### 🙈 隐藏菜单栏图标

不想让图标占菜单栏空间时可以隐藏。隐藏后**拦截依然生效**,只是没有菜单入口了。

为了不会「藏丢」,做了一个**逃生窗口**:

- **每次启动应用,图标都会先显示 10 秒**,菜单顶部提示「⏱ 菜单栏图标将在启动 10 秒后隐藏(打开菜单即保留)」
- 这 10 秒内**打开一次菜单**即取消本次隐藏,图标保留到退出为止
- 想找回图标:**退出并重新打开 慢Q** 即可

> 实现上踩到一个坑:macOS 会**持久化状态栏项的可见性**,所以隐藏过一次后,重启时新建的实例默认仍是隐藏的——逃生窗口根本不出现。修复方式是每次启动显式 `isVisible = true`,再由定时器决定是否隐藏。

### 🚀 登录时自动启动

基于系统的 `SMAppService` 登录项(而非已废弃的 `LSSharedFileList`),菜单里一键开关,状态带 ✓ 标记。

> 需要应用位于「应用程序」文件夹。若在开发目录里点击,会看到明确的错误提示 —— 系统不允许从任意路径注册登录项。

### ⏸ 定时暂停

「暂停拦截」提供 **5 / 15 / 60 分钟**,**到点自动恢复**,不用记得手动开回来。暂停期间菜单实时显示「还剩约 N 分钟」,也可随时点「立即恢复拦截」。

适合「接下来要连续退出好几个应用」的场景 —— 之前只能手动停用,然后常常忘记重新启用。

### ℹ️ 关于

显示版本号与项目地址,一键跳转 GitHub。

---

## 📥 下载 / Download

| 文件 | 说明 |
|---|---|
| `SlowQ-1.0.6-macos-universal.dmg` | 推荐。打开后把 SlowQ(慢Q)拖进 Applications |
| `SlowQ-1.0.6-macos-universal.zip` | 解压后拖进 Applications |

**通用二进制**,macOS 13 Ventura 及以上,支持 Apple Silicon 与 Intel Mac。

## ⚠️ 首次打开必读

本应用**未经 Apple 开发者签名与公证**,macOS 会拦截首次启动。执行一次:

```bash
xattr -dr com.apple.quarantine /Applications/SlowQ.app
```

或在 Finder 里**右键** → **打开** → 弹窗里再点 **打开**。

## 🔑 授予辅助功能权限

**系统设置 → 隐私与安全性 → 辅助功能 → 勾选「慢Q」**。

> **升级提示**:覆盖安装后辅助功能授权可能失效(adhoc 签名随二进制变化)。若拦截不工作,执行 `tccutil reset Accessibility com.slowq.app` 后重新勾选。

---

## English

### New in this release

- **Hide menu bar icon** — interception keeps working while the icon is hidden. Every launch shows the icon for the first 10 seconds with a menu hint; opening the menu during that window keeps it for the session. So the icon can never be lost — quit and relaunch to get it back.
  > Gotcha found while building this: macOS **persists status item visibility**, so after one hide a freshly created item is still hidden on the next launch and the 10-second window never appeared. Fixed by explicitly setting `isVisible = true` on every launch and letting a timer decide.
- **Launch at login** — uses the modern `SMAppService` login item (not the deprecated `LSSharedFileList`), toggled from the menu with a ✓ indicator. The app must live in `/Applications`; registering from a dev folder shows a clear error.
- **Timed pause** — pause for 5 / 15 / 60 minutes and it **re-enables itself**, with the remaining time shown live in the menu and an "resume now" action. Handy when you need to quit several apps in a row.
- **About** — shows the version and links to the project.

Download the `.dmg` or `.zip` below (universal binary, macOS 13+). Clear the quarantine flag once, then grant Accessibility permission. After upgrading over an older build the grant may need re-applying via `tccutil reset Accessibility com.slowq.app`.
