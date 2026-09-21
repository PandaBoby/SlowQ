# SlowQ v1.0.7 · 慢Q

> 修复「隐藏菜单栏图标后就找不回来」的问题。
> Fixes: once the menu bar icon was hidden there was no way to bring it back.

---

## 🐛 修复:隐藏图标后无法恢复

### 问题

v1.0.6 引入「隐藏菜单栏图标」时,设计的找回方式是"重启应用后图标会显示 10 秒"。但**实际根本行不通**:

> 隐藏后应用仍在后台运行。**再次打开它并不会重启进程**,`applicationDidFinishLaunching` 不会再次执行,
> 那个 10 秒逃生窗口永远不会触发 —— 而且此时连菜单都没有了,无法退出应用,只能去活动监视器强杀。

### 修复

**1. 再次打开应用即可恢复(核心修复)**

实现了 `applicationShouldHandleReopen`:在启动台 / 应用程序文件夹 / Dock 里**再点一次 慢Q**(哪怕它已经在运行),图标立刻回来,并自动清除隐藏设置。

实测:图标恢复 ✓、进程数仍为 1 ✓(不会重复启动)、重启后保持可见 ✓。

**2. 隐藏当场给出提示**

点击隐藏时,屏幕中央立刻弹出一条提示条(不依赖通知权限、不抢焦点):

```
菜单栏图标已隐藏 · 再次打开 慢Q 即可恢复
```

**3. 菜单项自说明**

菜单项标题改为「隐藏菜单栏图标(再次打开应用可恢复)」,在点击之前就说明后果。

**4. 保留启动时的 10 秒窗口**

启动后图标先显示 10 秒(菜单顶部有提示),这期间打开菜单也会取消隐藏。

> 另外查清了 macOS 的行为:它会把状态栏项的可见性**持久化到应用偏好**里
> (能看到 `NSStatusItem VisibleCC Item-0 = 0`),所以隐藏过一次后,重启时新建的实例默认仍是隐藏的 ——
> 这也是为什么必须显式置为可见。

---

## 📥 下载 / Download

| 文件 | 说明 |
|---|---|
| `SlowQ-1.0.7-macos-universal.dmg` | 推荐。打开后把 SlowQ(慢Q)拖进 Applications |
| `SlowQ-1.0.7-macos-universal.zip` | 解压后拖进 Applications |

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

### Fixed — hiding the menu bar icon was a one-way trip

**The problem.** v1.0.6 shipped "hide menu bar icon" with a safety net: every launch shows the icon for 10 seconds. In practice that never fires:

> The app keeps running in the background after hiding. **Opening it again does not relaunch the process**, so
> `applicationDidFinishLaunching` never runs again — and with the menu gone you cannot even quit it, short of
> force-quitting from Activity Monitor.

**The fix.**

1. **Open the app again to restore it** — implemented `applicationShouldHandleReopen`. Clicking 慢Q once more in Launchpad / Applications / the Dock (even while it is running) brings the icon straight back and clears the hidden setting. Verified: icon restored, still exactly one process, and it stays visible after a relaunch.
2. **A toast on hide** — an on-screen card appears immediately (no notification permission, no focus stealing): `菜单栏图标已隐藏 · 再次打开 慢Q 即可恢复`.
3. **Self-documenting menu item** — renamed to `隐藏菜单栏图标(再次打开应用可恢复)` so the consequence is clear before you click.
4. **The 10-second launch window remains** — the icon shows for 10 s on every launch, and opening the menu during that window cancels the hide.

> Also confirmed how macOS behaves: it **persists status item visibility in the app's preferences** (`NSStatusItem VisibleCC Item-0 = 0`), which is why a newly created item stays hidden after a previous hide — and why the item must be forced visible explicitly.

Download the `.dmg` or `.zip` below (universal binary, macOS 13+). Clear the quarantine flag once, then grant Accessibility permission.
