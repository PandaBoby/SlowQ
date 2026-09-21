# SlowQ — 防误触 ⌘Q(macOS 原生)

像 Chrome 那样:按住 **⌘Q** 一段时间(默认 3 秒)才退出应用,轻轻一按不会退出。对**所有应用**全局生效。

## 构建

```bash
./build-app.sh
```

生成 `SlowQ/SlowQ.app`(已包含 release 二进制)。系统要求 macOS 13+。

## 首次运行(必须授权一次)

macOS 要求拦截全局键盘事件的应用获得**辅助功能**权限:

1. 双击运行 `SlowQ.app`(或在终端 `open SlowQ/SlowQ.app`)
2. 打开 **系统设置 → 隐私与安全性 → 辅助功能**
3. 把 **SlowQ** 加入并勾选(如未自动出现,点 + 手动添加 SlowQ.app)
4. 重新启动 SlowQ

授权成功后,菜单栏会出现一个 ⏳ 图标。

## 使用

- 在任意应用按 **⌘Q**:屏幕中央弹出倒计时圆环(例如 3.0 → 0.0)
  - **按住不放**到 0 → 松手后真正退出该应用
  - **中途松开** → 倒计时消失,什么都不发生
- 菜单栏 ⏳ 图标:
  - 停用/启用拦截(临时关闭)
  - 调节按住时长:1 / 2 / 3 / 5 秒(会记住设置)
  - 退出 SlowQ 本身用 **⌥⌘Q**(避免自我拦截)

## 工作原理

- 使用 `CGEvent.tapCreate` 创建系统级键盘事件拦截(session event tap,head insert),接管所有应用的 ⌘Q
- 拦截期间吞掉 keyDown,同时监听 flagsChanged 检测 ⌘ 释放
- 达到时长后暂时停用 tap,向最前面的应用合成发送一次 ⌘Q 完成真实退出,再恢复拦截
- 菜单栏常驻(NSStatusItem),`LSUIElement` 使其不占 Dock

## 文件结构

```
SlowQ/
├── build-app.sh        # 一键构建脚本
└── SlowQ/
    ├── Package.swift
    ├── src/
    │   ├── main.swift          # 入口
    │   └── AppDelegate.swift   # 事件拦截 + 菜单栏 + HUD 倒计时
    └── SlowQ.app               # 构建产物(可直接双击)
```

## 故障排查

如果拦截不生效,按顺序检查:

1. **看日志**:`~/Library/Logs/SlowQ.log`,确认最后一行是 `event tap 安装成功`
2. **权限失效**(最常见):重新构建后 adhoc 签名变化会让 macOS 辅助功能授权失效。修复:
   ```bash
   tccutil reset Accessibility com.slowq.app
   # 然后重新打开 SlowQ,在系统设置中重新勾选
   ```
   > 实测:仅"关掉开关再重新打开"**不能**恢复授权——macOS 不会重新校验二进制,必须 `tccutil reset` 后重新勾选。
3. 菜单栏 ⏳ 图标确认 SlowQ 在运行、未被"停用"

## 界面

HUD 为现代深色毛玻璃卡片设计:

- 深色半透卡片 + 顶部高光渐变 + 自绘柔和阴影
- 中央 ⌘ 图标 + 大号等宽数字倒计时
- 进度圆环随进度从蓝色渐变到红色(蓝色=刚开始,红色=即将触发)
- 按住超过 70% 时圆环外圈出现红色脉冲光晕
- 到时后底部文案变为"松开以退出"
- 入场弹性缩放动画(CASpringAnimation),淡入淡出过渡
- CVDisplayLink 驱动每帧重绘,动画平滑

## 测试验证(已通过)

使用 Ghostty 实测:

- 短按 ⌘Q 0.3 秒 → 应用存活(连续 3 轮稳定)
- 按住 3.2 秒(含系统 key repeat)→ 正确退出
- HUD 反复显示/隐藏无崩溃
