# SlowQ v1.0.0

> 按住 `⌘Q` 满 3 秒才退出应用,告别误触。· Hold `⌘Q` for 3 seconds to quit — no more accidental quits.

首个公开版本。菜单栏常驻,系统级接管**所有应用**的 `⌘Q`。

---

## 📥 下载 / Download

| 文件 | 说明 |
|---|---|
| `SlowQ-1.0.0-macos-universal.dmg` | 推荐。打开后把 SlowQ 拖进 Applications |
| `SlowQ-1.0.0-macos-universal.zip` | 解压后把 `SlowQ.app` 拖进 Applications |

**通用二进制**:同时支持 Apple Silicon 与 Intel Mac(macOS 13 Ventura 及以上)。

---

## ⚠️ 首次打开必读(重要)

本版本**没有 Apple 开发者签名与公证**(需 99 美元/年的开发者账号),因此 macOS 会拦截。二选一:

**方式 A —— 命令行解除隔离(推荐,最可靠)**

```bash
xattr -dr com.apple.quarantine /Applications/SlowQ.app
```

**方式 B —— 右键打开**

在 Finder 里**右键**点 `SlowQ.app` → **打开** → 在弹窗里再点 **打开**。

> 如果系统提示「已损坏,无法打开」,说明方式 B 不适用,请用方式 A。

## 🔑 授予辅助功能权限

macOS 要求拦截全局键盘的应用必须获得**辅助功能**权限,否则拦截完全不生效:

1. 启动 SlowQ
2. 打开 **系统设置 → 隐私与安全性 → 辅助功能**
3. 勾选 **SlowQ**(列表中若没有,点 `+` 添加 `/Applications/SlowQ.app`)
4. SlowQ 会**自动检测到授权并立即生效**,无需重启

授权成功后菜单栏出现蜗牛图标。

---

## ✨ 本版功能

- 🌐 **全局接管** —— 基于 `CGEventTap` 的系统级拦截,任意应用生效,无需逐应用配置
- ⏱️ **时长可调** —— 菜单栏切换 1 / 2 / 3 / 5 秒,自动记忆
- 🎨 **精致 HUD** —— 深色毛玻璃卡片 + 弹性入场动画 + 蓝→红渐变进度环 + 临近触发的脉冲光晕
- 🔒 **隐私优先** —— 日志默认关闭;开启后也**只记录 `⌘Q` 事件**,绝不落盘其他按键
- 🪶 **轻量常驻** —— 菜单栏应用不占 Dock,动画循环仅在 HUD 显示时运行
- 🚫 **随时停用** —— 菜单栏一键暂停;退出自身用 `⌥⌘Q`,避免自我拦截

## 🎬 使用

任意应用按 `⌘Q` → 屏幕中央浮出倒计时圆环:

- **按住满设定时长** → 提示变为「松开以退出」,松手后该应用退出
- **中途松手** → 浮层淡出,什么都不会发生

## ⚙️ 配置

```bash
defaults write com.slowq.app holdSeconds -float 3            # 长按时长(秒)
defaults write com.slowq.app statusIconTemplate -bool true   # 菜单栏图标:单色模板
defaults write com.slowq.app debugLog -bool true             # 调试日志(默认关闭)
tail -f ~/Library/Logs/SlowQ.log                             # 查看日志
```

## 🐞 已知问题

- **菜单栏图标在深色模式下不可见**:当前图标为纯黑剪影,彩色模式在深色菜单栏下会看不见。菜单里切换为「单色」即可自动适配。
- **重新构建后辅助功能授权可能失效**:adhoc 签名随二进制变化。修复:
  ```bash
  tccutil reset Accessibility com.slowq.app
  # 重新打开 SlowQ 并重新勾选
  ```

## 🙏 反馈

遇到问题或想提需求,欢迎开 [Issue](https://github.com/PandaBoby/SlowQ/issues)。

---

## English

**First public release.** A menu bar utility that takes over the global `⌘Q` in every app.

**Download** the `.dmg` (drag to Applications) or the `.zip`. Universal binary — Apple Silicon and Intel, macOS 13+.

**⚠️ First launch:** the app is **not Developer ID signed or notarized**, so macOS will block it. Either run:

```bash
xattr -dr com.apple.quarantine /Applications/SlowQ.app
```

or right-click `SlowQ.app` → **Open** → **Open** again in the dialog.

**Accessibility permission is required** for interception to work: System Settings → Privacy & Security → Accessibility → tick **SlowQ**. SlowQ detects the grant automatically — no restart needed.

**Features:** system-wide `⌘Q` interception via `CGEventTap` · adjustable 1/2/3/5-second hold · polished glass HUD with a blue→red progress ring · logging off by default and `⌘Q`-only when enabled · menu bar only, no Dock icon · pause anytime from the menu, quit with `⌥⌘Q`.

**Usage:** press `⌘Q` anywhere, hold the countdown ring to completion, release to quit. Releasing early cancels.

