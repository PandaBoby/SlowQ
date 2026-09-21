<div align="center">

<img src="SlowQ/SlowQ.png" width="112" alt="SlowQ">

# SlowQ

**按住 ⌘Q 满 3 秒才退出 —— 告别误触退出应用**

一个接管全局 ⌘Q 的 macOS 原生小工具

[![Platform](https://img.shields.io/badge/macOS-13%2B-black?logo=apple&logoColor=white)](#系统要求)
[![Swift](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)](#项目结构)
[![UI](https://img.shields.io/badge/UI-AppKit-1E90FF)](#工作原理)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)
[![Stars](https://img.shields.io/github/stars/PandaBoby/SlowQ?style=flat&color=yellow)](https://github.com/PandaBoby/SlowQ/stargazers)

**中文** · [English](README.en.md)

</div>

---

## 这是什么

在 macOS 上,`⌘Q` 会**立刻**退出当前应用——正在编辑的文档、没保存的草稿、跑着的任务,一次误触就没了。

SlowQ 把 `⌘Q` 变成"需要按住"的操作:按下时屏幕中央浮出倒计时圆环,**按住满 3 秒**才真正退出,**中途松手立即取消**。它通过系统级事件拦截接管**所有应用**的 `⌘Q`,无需逐个配置。

> 灵感来自 Chrome 的 "Hold ⌘Q to quit"。

## 特性

|  |  |
|---|---|
| 🌐 **全局接管** | 基于 `CGEventTap` 的系统级拦截,对任意应用生效,无需逐应用设置 |
| ⏱️ **可调时长** | 菜单栏一键切换 1 / 2 / 3 / 5 秒,设置自动记忆 |
| 🎨 **精致 HUD** | 深色毛玻璃卡片 + 弹性入场动画 + 蓝→红渐变进度环 + 即将触发时的脉冲光晕 |
| 🔒 **隐私优先** | 日志默认关闭;开启后也只记录 `⌘Q` 事件,绝不落盘其他按键 |
| 🪶 **轻量常驻** | 菜单栏应用,不占 Dock;动画循环仅在 HUD 显示时运行,空闲零开销 |
| 🚫 **可随时停用** | 菜单栏一键暂停拦截,退出自身用 `⌥⌘Q` 避免自我拦截 |

## 效果

按下 `⌘Q` 时,屏幕中央出现这样的浮层(圆环随进度由蓝转红填充):

```text
        ╭──────────────────────────╮
        │            ⌘             │
        │         ╭──────╮         │
        │        ╱        ╲        │
        │       │   2.4    │       │
        │        ╲        ╱        │
        │         ╰──────╯         │
        │                          │
        │       按住 ⌘Q 退出       │
        ╰──────────────────────────╯
```

- **按住到 0.0** → 底部文案变为「松开以退出」,松手后应用退出
- **提前松手** → 浮层淡出,什么都不会发生

## 系统要求

- macOS **13 (Ventura)** 或更高
- 构建需要 Xcode Command Line Tools(`xcode-select --install`)

## 安装

### 方式一:下载预编译包(推荐)

从 [**Releases**](https://github.com/PandaBoby/SlowQ/releases/latest) 下载:

| 文件 | 说明 |
|---|---|
| `SlowQ-x.y.z-macos-universal.dmg` | 推荐。打开后把 SlowQ 拖进 Applications |
| `SlowQ-x.y.z-macos-universal.zip` | 解压后把 `SlowQ.app` 拖进 Applications |

> **通用二进制**,同时支持 Apple Silicon 与 Intel Mac。

**首次打开必读 ⚠️** —— 本应用未做 Apple 开发者签名与公证(需 99 美元/年的账号),macOS 会拦截首次启动。执行一次即可:

```bash
xattr -dr com.apple.quarantine /Applications/SlowQ.app
```

或者在 Finder 里**右键**点 `SlowQ.app` → **打开** → 在弹窗里再点 **打开**。

> 若提示「已损坏,无法打开」,说明右键方式不适用,请用上面的 `xattr` 命令。

### 方式二:从源码构建

```bash
git clone https://github.com/PandaBoby/SlowQ.git
cd SlowQ
./build-app.sh          # 构建通用二进制并打包为 SlowQ/SlowQ.app
open SlowQ/SlowQ.app
```

需要 Xcode Command Line Tools(`xcode-select --install`)。`build-app.sh` 会自动完成:生成菜单栏图标 → 编译(arm64 + x86_64)→ 打包 `.app` → 生成 `.icns` → adhoc 签名。

发布打包用 `./release.sh`(产出 zip/dmg 到 `dist/`),加 `--publish` 可直接创建 GitHub Release。

## ⚠️ 首次运行必须授权

macOS 要求拦截全局键盘事件的应用获得**辅助功能**权限,否则拦截完全不生效:

1. 启动 `SlowQ.app`
2. 打开 **系统设置 → 隐私与安全性 → 辅助功能**
3. 找到 **SlowQ** 并勾选(若列表中没有,点 `+` 手动添加 `SlowQ/SlowQ.app`)
4. SlowQ 会**自动检测**到授权并立即生效,无需重启

授权成功后菜单栏出现蜗牛图标。验证是否生效:看 `~/Library/Logs/SlowQ.log` 是否出现 `event tap 安装成功`(需先开启日志,见下)。

## 使用

**拦截 ⌘Q**

- 任意应用按 `⌘Q` → 浮层出现 → 按住满设定时长 → 松手退出该应用
- 中途松手 → 取消

**菜单栏图标**

| 菜单项 | 作用 |
|---|---|
| 停用 / 启用拦截 ⌘Q | 临时关闭拦截(如需要连续退出多个应用) |
| 按住时长 → 1/2/3/5 秒 | 调整长按时长,自动记忆 |
| 菜单栏图标:彩色 / 单色 | 切换图标为彩色原色或单色模板(单色会随菜单栏深浅自动变色) |
| 退出 SlowQ (⌥⌘Q) | 退出 SlowQ 自身(用 `⌥⌘Q` 避免被自己拦截) |

## 工作原理

```text
   物理 ⌘Q
      │
      ▼
┌─────────────────────────────┐
│  CGEventTap                 │  ← session 级、head insert,先于所有应用拿到事件
│  (keyDown / keyUp / flags)  │
└─────────────┬───────────────┘
              │ 吞掉 ⌘Q,启动计时
              ▼
      ┌───────────────┐
      │  状态机        │  idle → holding → fired
      │  holding 期间  │  吞掉所有 key repeat
      └───────┬───────┘
              │ 计时达到阈值
              ▼
      ┌───────────────┐
      │ 向最前台应用   │  postToPid 投递一次合成 ⌘Q
      │ 投递合成 ⌘Q   │  (投递期间暂停 tap,避免自我拦截)
      └───────────────┘
```

几个关键设计:

- **key repeat 必须吞掉**:按住键时系统会持续补发 `keyDown`,只拦第一个会导致应用被后续 repeat 立刻退出 —— 早期版本的"不生效"就是这个 bug
- **`postToPid` 而非 `CGEventPost`**:定向投递给目标进程,不经会话 tap,因此不会与自身拦截形成循环
- **暂停窗口兜底**:投递合成事件时 tap 会短暂停用,期间到达的**物理** `⌘Q` 同样被吞掉,防止绕过
- **授权轮询**:启动时若未授权则每秒检测,授权后自动装载 tap,无需重启

## 配置

设置通过 `UserDefaults`(domain `com.slowq.app`)持久化:

```bash
defaults write com.slowq.app holdSeconds -float 3      # 长按时长(秒)
defaults write com.slowq.app statusIconTemplate -bool true   # 菜单栏图标:单色模板
defaults write com.slowq.app debugLog -bool true       # 调试日志(默认关闭)

# 查看日志
tail -f ~/Library/Logs/SlowQ.log
```

## 项目结构

```text
SlowQ/
├── build-app.sh                  # 一键构建:图标 → 编译 → 打包 → 签名
├── tools/
│   └── gen-statusbar.swift       # 菜单栏图标生成器(裁透明边距 + 等比缩放)
├── SlowQ/
│   ├── Package.swift             # SwiftPM 清单
│   ├── SlowQ.png / .svg          # 图标源(替换后重新构建即可换图标)
│   └── src/
│       ├── main.swift            # 入口
│       ├── AppDelegate.swift     # 事件拦截 + 状态机 + 菜单栏 + HUD
│       └── Resources/            # 生成好的菜单栏图标(1x / 2x)
└── README.md / README.en.md
```

## 故障排查

**拦截不生效**

1. 确认菜单栏有 SlowQ 图标(没有说明进程没起来)
2. 检查辅助功能权限是否被勾选
3. **重新构建后权限可能失效**:adhoc 签名会随二进制变化,导致 macOS 认为这不是同一个应用。修复:
   ```bash
   tccutil reset Accessibility com.slowq.app
   # 然后重新打开 SlowQ,在系统设置中重新勾选
   ```
   > 实测:仅"关掉开关再打开"**不足以**恢复授权,必须 `tccutil reset` 后重新勾选。

**菜单栏图标在深色模式下看不见**

当前图标是纯黑剪影,彩色模式在深色菜单栏下不可见。菜单里切换为**单色**即可自动适配。

**想换图标**

替换 `SlowQ/SlowQ.png`(建议 1024×1024 或更高的透明背景 PNG)后重新运行 `./build-app.sh`。

## 开发

```bash
cd SlowQ
swift build            # 调试构建
swift build -c release # 发布构建
```

改完源码后跑 `./build-app.sh` 重新打包;改了图标源则重复同样命令即可。

## 许可证

本项目基于 [Apache License 2.0](LICENSE) 开源。

```text
Copyright 2026 PandaBoby

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0
```

<div align="center">

**[⬆ 回到顶部](#slowq)** · [English README](README.en.md)

</div>
