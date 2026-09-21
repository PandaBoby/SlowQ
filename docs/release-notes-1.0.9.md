# SlowQ v1.0.9 · 慢Q

> 修复合盖睡眠唤醒后 ⌘Q 拦截静默失效,并修掉长期运行的内存泄漏与若干卡死路径。
> Fixes ⌘Q interception silently dying after sleep/wake, plus a long-run memory leak and several stuck paths.

---

## 🐛 修复

### 合盖睡眠再唤醒后,⌘Q 拦截失效(本次最重要)

**症状**:合上盖子睡眠、再打开唤醒之后,按住 ⌘Q 不再出现进度环,⌘Q 直接被前台 App 执行;但 慢Q 进程仍在运行,菜单栏图标也还在。只有手动重启 App 才能恢复。

**原因**:睡眠会让系统作废事件拦截(event tap)底层的 Mach port,但 App 侧持有的引用仍然非空,于是被当成"还在工作":

- 失效之后回调不再被调用,而"被系统禁用时自动重启拦截"的补救逻辑写在回调**里面**——它挂在已经死掉的东西上,永远不会执行;
- 拦截的安装函数只判断"引用非空"就提前返回,把陈旧端口当成已装好,任何恢复路径都被它挡掉;
- 此前全应用只监听了"退出"一个系统通知,**唤醒之后根本没有重建拦截的时机**。

**修复**:补齐睡眠/唤醒、解锁/切回会话、显示器配置变化等系统通知;用端口有效性做真实判活;失效时整体重建拦截;并增加一个 5 秒一次的看门狗兜底——因为一旦拦截死掉,只有"从外部"看才可能发现。

### 长期运行的内存泄漏

事件回调在放行按键时多持有了一个引用。拦截订阅的是**全系统的每一次按键**,因此每敲一个键就泄漏一个事件对象,内存随打字量无界增长。6 处全部改为正确的不增加引用计数写法。

### 合成退出后拦截可能永久卡死

按住满时长后会短暂暂停拦截、向前台 App 发送一次 ⌘Q。原先这段"等待 ⌘ 松开"的轮询既没有超时也没有被持有:如果 ⌘ 的松开事件被睡眠转换吞掉,暂停状态会永远保持,拦截从此处于物理禁用且无人恢复——**症状与上面那条完全一样**。现在加了 1.5 秒硬超时,并增加暂停超时的看门狗复位。

### 跨睡眠的"幻影退出"

按住 ⌘Q 的过程中合盖睡眠,唤醒后计时会接着上次的进度继续算,把你几小时前已经放弃的那次按住兑现成一次真实退出——向唤醒后最前面的 App 投递 ⌘Q,有丢失未保存内容的风险。现在进入睡眠时立即把状态机与 HUD 归零,并作废计时器。

### 进度环动画冻结

动画刷新所用显示链接在停止时没有被释放,启动时便一直复用睡眠前创建的那个(它绑定的是当时的显示器配置),睡眠或显示器变化后可能不再回调,表现为按住时进度环卡住不动。现在停止时释放、启动时按当前显示器重建。

### 图标着色路径的强制转换

将 `as!` 改为防御性转换,失败时优雅降级为不绘制图标而不是崩溃。此前本机曾在该路径上产生过一次崩溃报告(`Swift runtime failure: unexpectedly found nil while unwrapping an Optional`)。

---

## 🔧 改进

- **权限检查不再常驻轮询**:原先未授权时每秒轮询一次、且计时器永不失效,会跑满整个进程生命周期;现在统一由 5 秒看门狗承担,授权恢复后会自动装好拦截并刷新菜单。
- **简化启动保活**:移除冗余的 objc 关联对象,只保留一种持有方式,消除关联键地址冲突的隐患。
- **日志格式修正**,并补上"重新打开应用"路径下的空值保护。

---

## 📥 下载 / Download

| 文件 | 说明 |
|---|---|
| `SlowQ-1.0.9-macos-universal.dmg` | 推荐。打开后把 SlowQ(慢Q)拖进 Applications |
| `SlowQ-1.0.9-macos-universal.zip` | 解压后拖进 Applications |

**通用二进制**,macOS 13 Ventura 及以上,支持 Apple Silicon 与 Intel Mac。

## ⚠️ 首次打开必读

本应用**未经 Apple 开发者签名与公证**,macOS 会拦截首次启动。执行一次:

```bash
xattr -dr com.apple.quarantine /Applications/SlowQ.app
```

## 🔑 授予辅助功能权限

**系统设置 → 隐私与安全性 → 辅助功能 → 勾选「慢Q」**。

> **升级提示**:覆盖安装后辅助功能授权可能失效(adhoc 签名随二进制变化)。若拦截不工作,执行 `tccutil reset Accessibility com.slowq.app` 后重新勾选。

**本次升级强烈建议执行这一条** —— 这个版本专门修的就是"拦截静默失效",如果授权没勾上,会看起来像是没修好。

---

## English

### Fixed: ⌘Q interception died after closing the lid

**Symptom**: after sleeping the Mac (closing the lid) and waking it, holding ⌘Q no longer showed the progress ring and ⌘Q went straight through to the frontmost app — yet 慢Q was still running with its menu bar icon present. Only restarting the app brought it back.

**Cause**: sleep invalidates the Mach port behind the event tap, while the app's reference to it stayed non-nil and was therefore treated as healthy:

- once invalidated the callback is never invoked again — and the "re-enable when the system disables it" recovery lived *inside* that callback, i.e. attached to the thing that had already died;
- the install routine bailed out early whenever the reference was merely non-nil, so every recovery path was blocked;
- the app only observed the "terminate" notification, so **nothing ever triggered a rebuild after wake**.

**Fix**: sleep/wake, unlock/session-activation and display-configuration notifications are now observed; liveness is decided by actual port validity; a dead tap is fully rebuilt; and a 5-second watchdog backstops it — because once the tap dies, only an *external* check can notice.

### Fixed: memory leak during long runs

The event callback over-retained every event it passed through. The tap subscribes to **every keystroke system-wide**, so each key press leaked an event object. All six sites now use the correct non-retaining return.

### Fixed: interception could wedge permanently after a synthetic quit

After a full hold, interception is briefly paused while a ⌘Q is sent to the frontmost app. The "wait for ⌘ release" poll had neither a timeout nor an owner: if the key-up was swallowed by the sleep transition, the paused state persisted forever, leaving the tap physically disabled with nobody to recover it — **the same symptom as the headline bug**. A 1.5 s hard timeout and a paused-state watchdog reset were added.

### Fixed: phantom quit across sleep

Sleeping mid-hold let the timer resume where it left off after wake, cashing in a hold you had abandoned hours earlier as a real quit — posting ⌘Q to whatever app was frontmost, with a risk of losing unsaved work. State and HUD are now reset on sleep and the timer invalidated.

### Fixed: frozen progress ring

The animation display link was never released on stop, so it kept reusing the one created against the pre-sleep display configuration and could stop delivering callbacks after sleep or a display change. It is now released on stop and rebuilt against the current display on start.

### Fixed: force cast on the icon tinting path

`as!` replaced with a defensive conversion that degrades to "no icon" instead of crashing. This path had previously produced a crash report on this machine (`Swift runtime failure: unexpectedly found nil while unwrapping an Optional`).

### Improvements

- **No more permanent permission polling**: the old 1 Hz poll (never invalidated) ran for the whole process lifetime when permission was not granted; it is now covered by the 5 s watchdog, which installs the tap and refreshes the menu once permission returns.
- **Simpler startup ownership**: the redundant objc associated object was removed, leaving a single retention mechanism.
- Log format corrected, plus a nil guard on the "reopen app" path.

### Upgrade note

Replacing the app changes the ad-hoc signature, so the Accessibility grant may be invalidated. If interception does not work, run `tccutil reset Accessibility com.slowq.app` and tick 慢Q again — **this is strongly recommended for this release**, since the whole point of the update is to stop interception from failing silently.

Download the `.dmg` or `.zip` below (universal binary, macOS 13+). Clear the quarantine flag once, then grant Accessibility permission.
