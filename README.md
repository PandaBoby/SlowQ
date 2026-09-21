<div align="center">

<img src="SlowQ/SlowQ.png" width="112" alt="SlowQ 慢Q">

# SlowQ · 慢Q

**防误触退出助手**

> 退一步，再确认。

一个接管全局 ⌘Q 的 macOS 原生菜单栏工具

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

SlowQ(慢Q)把 `⌘Q` 变成"需要按住"的操作:按下时屏幕中央浮出倒计时圆环,**按住满 3 秒**才真正退出,**中途松手立即取消**。它通过系统级事件拦截接管**所有应用**的 `⌘Q`,无需逐个配置。

> 灵感来自 Chrome 的 "Hold ⌘Q to quit"。

## 特性

|  |  |
|---|---|
| 🌐 **全局接管** | 基于 `CGEventTap` 的系统级拦截,对任意应用生效,无需逐应用设置 |
| ⏱️ **可调时长** | 菜单栏一键切换 1 / 2 / 3 / 5 秒,设置自动记忆 |
| 🎨 **精致 HUD** | 深色毛玻璃卡片 + 弹性入场动画 + 蓝→红渐变进度环 + 即将触发时的脉冲光晕 |
| 🔒 **隐私优先** | 日志默认关闭;开启后也只记录 `⌘Q` 事件,绝不落盘其他按键 |
| 🪶 **轻量常驻** | 菜单栏应用,不占 Dock;动画循环仅在 HUD 显示时运行,空闲零开销 |
| 🚫 **可随时停用** | 菜单栏一键暂停拦截;支持 5/15/60 分钟定时暂停并自动恢复 |
| 🚀 **登录自启** | 可设为登录时自动启动,常驻守护不用手动打开 |
| 🙈 **图标可隐藏** | 隐藏菜单栏图标;每次启动保留 10 秒逃生窗口,不会「藏丢」 |

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

从 [**Releases**](https://github.com/PandaBoby/SlowQ/releases/latest) 下载(Gitee 镜像同步发布:[**Gitee Releases**](https://gitee.com/pandaboby/SlowQ/releases)):

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
git clone https://github.com/PandaBoby/SlowQ.git   # 或 Gitee: https://gitee.com/pandaboby/SlowQ.git
cd SlowQ
./build-app.sh          # 构建通用二进制并打包为 SlowQ/.build-app/SlowQ.app
open SlowQ/.build-app/SlowQ.app
```

需要 Xcode Command Line Tools(`xcode-select --install`)。`build-app.sh` 会自动完成:生成菜单栏图标 → 编译(arm64 + x86_64)→ 打包 `.app` → 生成 `.icns` → adhoc 签名。

> 开发构建产物放在隐藏目录 `.build-app/` 下,Spotlight 不索引点号目录,因此它**不会出现在 Launchpad 或 Finder 搜索里**,不会和 `/Applications` 里的正式版重复。

发布打包用 `./release.sh`(产出 zip/dmg 到 `dist/`):

```bash
./release.sh --publish          # 发布 GitHub Release
./release.sh --gitee            # 发布 Gitee Release(需 ~/.token/gitee-token)
./release.sh --publish --gitee  # 两边同时发布
```

## ⚠️ 首次运行必须授权

macOS 要求拦截全局键盘事件的应用获得**辅助功能**权限,否则拦截完全不生效:

1. 启动 `SlowQ.app`(中文系统显示为「慢Q」)
2. 打开 **系统设置 → 隐私与安全性 → 辅助功能**
3. 找到 **慢Q**(英文系统显示 **SlowQ**)并勾选 —— 若列表中没有,点 `+` 手动添加 `/Applications/SlowQ.app`(开发构建为 `SlowQ/.build-app/SlowQ.app`)
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
| 暂停拦截 → 5 / 15 / 60 分钟 | 定时暂停,**到点自动恢复**,菜单里实时显示剩余时间 |
| 按住时长 → 0.5/1/2/3/5 秒 | 调整长按时长,自动记忆 |
| 登录时自动启动 | 开机自动运行(基于系统 `SMAppService` 登录项) |
| 隐藏菜单栏图标 | 隐藏菜单栏图标,适合不想让它占菜单栏空间的用户 |
| 关于 慢Q | 查看版本与项目地址 |
| 退出 慢Q (⌥⌘Q) | 退出 SlowQ 自身(用 `⌥⌘Q` 避免被自己拦截) |

**关于「隐藏菜单栏图标」的找回方式**

图标隐藏后拦截**依然生效**,只是菜单栏上没有入口了。找回方式:

> ### 🐌 再次打开 慢Q 即可
> 在 **启动台 / 应用程序文件夹 / Dock** 里再点一次 慢Q(即使它已经在后台运行),
> 菜单栏图标就会立刻回来,同时**屏幕顶部中央**会弹出一条「菜单栏图标已恢复」的提示。

几个细节:

- 点击隐藏时,**屏幕顶部中央**会立刻弹出**「菜单栏图标已隐藏 · 再次打开 慢Q 即可恢复」**的提示条,当场告诉你找回路子
- 重新打开**不会**启动第二个进程 —— 只是把图标显示回来,并自动清除「隐藏」设置
- 另外每次启动应用时,图标都会先显示 **10 秒**;这 10 秒内打开一次菜单也会取消隐藏

> 实现细节:macOS 会把状态栏项的可见性持久化到应用偏好里(`NSStatusItem VisibleCC …`),隐藏过一次后,重启时新建的实例默认仍是隐藏的 —— 所以代码里每次启动都显式置为可见,并实现了 `applicationShouldHandleReopen` 来响应"再次打开应用"。

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
defaults write com.slowq.app statusIconTemplate -bool true   # 强制菜单栏图标为单色(默认:自动识别)
defaults write com.slowq.app debugLog -bool true       # 调试日志(默认关闭)

# 查看日志
tail -f ~/Library/Logs/SlowQ.log
```

## 项目结构

```text
SlowQ/
├── build-app.sh                  # 一键构建:图标 → 编译 → 打包 → 签名
├── tools/
│   ├── gen-statusbar.swift       # 菜单栏图标生成器(裁透明边距 + 等比缩放)
│   └── gen-appicon.swift         # App 图标生成器(保持宽高比,避免拉伸)
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

**菜单栏图标在深色菜单栏下看不清**

SlowQ 使用**自动**模式:若图标本身是单色(如纯黑剪影),会自动作为模板图使用,由系统按菜单栏明暗渲染(深色→白色、浅色→黑色),不会出现黑图标配黑背景;有真实彩色的图标则保留原色。

只有当你在终端手动设过 `defaults write com.slowq.app statusIconTemplate -bool false`(强制彩色)且图标恰好是纯黑时才可能隐形,恢复自动:

```bash
defaults delete com.slowq.app statusIconTemplate
```

**想换图标**

替换 `SlowQ/SlowQ.png`(建议 1024×1024 或更高的透明背景 PNG)后重新运行 `./build-app.sh`。

## 开发

```bash
cd SlowQ
swift build            # 调试构建
swift build -c release # 发布构建
```

改完源码后跑 `./build-app.sh` 重新打包;改了图标源则重复同样命令即可。

## 命名与品牌

| 项 | 内容 |
|---|---|
| 应用名 | SlowQ |
| 中文名 | 慢Q |
| 中文副标题 | 防误触退出助手 |
| App Store 标题 | 慢Q - 防误触退出 |
| GitHub 描述 | SlowQ(慢Q)—— 防止误触 Command+Q 退出的 macOS 菜单栏工具 |
| 中文 Slogan | 退一步,再确认。 |
| 英文 Slogan | Slow down quitting. |

中文系统下应用显示为 **慢Q**(通过 `InfoPlist.strings` 本地化),英文系统显示 **SlowQ** —— 因此 Finder 图标名与「辅助功能」权限列表里出现的都是 **慢Q**。

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
