import Cocoa
import Carbon.HIToolbox
import ApplicationServices
import ServiceManagement

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // 按住阈值(秒),可在菜单中调节
    private var holdSeconds: Double = 3.0
    private var enabled = true

    // ── 实用功能状态 ──
    /// 是否隐藏菜单栏图标(持久化)。隐藏后只能通过重新启动应用找回图标,
    /// 因此每次启动都会先显示 10 秒作为"逃生窗口"。
    private var statusItemHidden: Bool {
        get { UserDefaults.standard.bool(forKey: "statusItemHidden") }
        set { UserDefaults.standard.set(newValue, forKey: "statusItemHidden") }
    }
    private var autoHideTimer: Timer?
    /// 定时暂停的截止时间;nil 表示未定时暂停
    private var pauseUntil: Date?
    private var pauseTimer: Timer?

    // 状态机
    private var holding = false
    private var holdStartTime: CFTimeInterval = 0
    private var fired = false // 本轮是否已放行/执行退出
    /// 按住进度计时器。必须可作废:跨睡眠的残留计时会把一次早已放弃的
    /// 按住兑现成真实退出(见 handleWillSleep / resetState)。
    private var holdTimer: Timer?
    /// 等待 ⌘ 松开的轮询计时器。必须可作废且带超时(见 waitForCommandReleaseThenSend)。
    private var commandReleaseTimer: Timer?

    private var hudWindow: OverlayWindow?
    /// HUD 显示代数:每次 showHUD 递增,用于作废在途的淡出完成回调(见 hideHUD)
    private var hudGeneration = 0
    var toastWindow: ToastWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("启动")
        holdSeconds = UserDefaults.standard.double(forKey: "holdSeconds")
        if holdSeconds <= 0 { holdSeconds = 3.0 }

        registerTerminateObserver()
        registerLifecycleObservers()

        // 无论是否已授权都先显示菜单栏图标,让用户能立即看到应用已启动、
        // 并可随时从菜单退出或打开权限设置(否则未授权时图标不出现,容易被当成没启动)。
        setupStatusItem()

        // 若用户设过"隐藏菜单栏图标",每次启动仍先显示 10 秒 ——
        // 否则图标一旦隐藏就再也没有入口把它找回来(只能靠删偏好文件)。
        if statusItemHidden {
            log("菜单栏图标处于隐藏设置,启动后 10 秒自动隐藏")
            scheduleAutoHide(after: 10)
            rebuildMenu()   // 让菜单顶部出现"即将自动隐藏"的提示项
        }

        // 主动检查辅助功能权限
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                as CFDictionary
        )
        if trusted {
            log("辅助功能权限 OK")
            if !installEventTap() {
                // 启动时已可信但 tap 创建失败(罕见):交给看门狗重试
                log("tap 创建失败,交由看门狗重试")
            }
        } else {
            log("未获得辅助功能权限,等待授权;看门狗会持续重试")
        }
    }

    /// 幂等注册终止观察者(仅注册一次)
    private var terminateObserverRegistered = false
    private func registerTerminateObserver() {
        guard !terminateObserverRegistered else { return }
        terminateObserverRegistered = true
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.uninstallEventTap()
            self.tapWatchdogTimer?.invalidate()
            self.tapWatchdogTimer = nil
        }
    }

    // MARK: 睡眠 / 唤醒 / 会话恢复
    //
    // 这一段解决的是「合盖睡眠再唤醒后 ⌘Q 不再被拦截,但进程仍在运行、
    // 菜单栏图标也还在」这一故障。原因链:
    //   ① 睡眠会让 session 级 event tap 的底层 Mach port 被系统作废;
    //   ② 端口作废后回调永不再被调用 —— 写在 handleEvent 里的
    //      .tapDisabledByTimeout / .tapDisabledByUserInput 自愈分支
    //      也就永远不会执行(它挂在已经死掉的东西上);
    //   ③ installEventTap 原本只判 `eventTap != nil` 就早退,
    //      把陈旧端口当成"已装好",任何恢复路径都会被它挡掉;
    //   ④ 此前全应用只注册了 willTerminate 一个观察者,
    //      唤醒之后根本没有重建时机。
    // 因此必须补齐:外部可触发的体检 + 端口有效性校验 + 全量重建 + 看门狗兜底。

    private var lifecycleObserversRegistered = false

    /// 注册睡眠/唤醒/会话/显示器变化观察者(幂等)
    private func registerLifecycleObservers() {
        guard !lifecycleObserversRegistered else { return }
        lifecycleObserversRegistered = true

        let workspaceCenter = NSWorkspace.shared.notificationCenter

        // 即将睡眠:立刻把按住状态归零。
        // CACurrentMediaTime() 在睡眠期间不推进,若不清理,唤醒后 0.05s
        // 计时器会接着上次的进度继续算,把用户几小时前放弃的那次"按住"
        // 兑现成一次真实退出 —— 向唤醒后最前面的 App 投递合成 ⌘Q。
        workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleWillSleep()
        }

        // 唤醒(整机 / 显示器):校验并按需重建 tap
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.recoverAfterWake(reason: name.rawValue)
            }
        }

        // 解锁 / 切换回本用户会话:session tap 常在此期间被系统禁用
        workspaceCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.ensureEventTapHealthy(reason: "sessionDidBecomeActive")
        }

        // 应用重新激活:accessory 应用被点击或打开菜单时也会走到,作为额外兜底
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.ensureEventTapHealthy(reason: "didBecomeActive")
        }

        // 显示器配置变化(含唤醒后重建显示器):tap 需复查,动画 link 需重连
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.ensureEventTapHealthy(reason: "screenParametersChanged")
            self.hudWindow?.recentreOnCurrentScreen()
            self.hudWindow?.progress.refreshAnimationIfVisible()
        }

        startTapWatchdog()
    }

    private func handleWillSleep() {
        log("系统即将睡眠,重置按住状态")
        resetState()
        // 暂停窗口也必须一并清掉:睡眠会作废 tap 端口,唤醒后 keyState(⌘)
        // 大概率已是 false,残留的 commandReleaseTimer 会在第一个 tick 就把
        // 一条真实合成 ⌘Q 投给唤醒后最前面的应用 —— 与 holdTimer 同型的
        // 「跨睡眠兑现」问题。
        commandReleaseTimer?.invalidate()
        commandReleaseTimer = nil
        if eventTapIsPaused { eventTapIsPaused = false }
    }

    /// 唤醒后:先归零状态机,再校验拦截是否还活着
    private func recoverAfterWake(reason: String) {
        log("系统已唤醒(\(reason)),校验事件拦截")
        resetState()
        ensureEventTapHealthy(reason: reason)
    }

    // MARK: 事件 tap 体检 / 看门狗

    private var tapWatchdogTimer: Timer?
    /// 进入暂停的时刻,用于给合成退出的暂停窗口加硬超时(见 watchdogTick)
    private var pausedAt: Date?

    /// tap 是否真的可用。
    /// `eventTap != nil` 完全不足以判活:睡眠/唤醒后系统作废的是底层 Mach port,
    /// Swift 侧的 CFMachPort 引用依旧非 nil,不会变 nil 也不会报错。
    private var isEventTapHealthy: Bool {
        guard let tap = eventTap, CFMachPortIsValid(tap) else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    /// 外部定期体检。回调内自愈在 tap 已死时永远不会触发,所以必须有人在"外面"看。
    private func startTapWatchdog() {
        tapWatchdogTimer?.invalidate()
        tapWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.watchdogTick()
        }
    }

    private func watchdogTick() {
        // 暂停窗口正常只有 ~0.3s;超时未复位说明恢复路径丢了(例如 ⌘ 的 keyUp
        // 被睡眠转换吞掉)。此时 tap 处于物理禁用状态且无人再管,必须强制复位。
        if eventTapIsPaused, let since = pausedAt, Date().timeIntervalSince(since) > 3 {
            log("合成退出暂停状态超时,强制复位")
            eventTapIsPaused = false
            resetState()
        }
        ensureEventTapHealthy(reason: "watchdog")
    }

    /// 所有恢复路径(唤醒 / 会话激活 / 显示器变化 / 看门狗)的唯一入口:体检 + 按需修复。
    private func ensureEventTapHealthy(reason: String) {
        // 暂停窗口(合成 ⌘Q 前后)内不干预,否则会破坏"暂停期间不放行"的契约
        guard !eventTapIsPaused else { return }
        // 授权被回收时无法重建(重装/升级后常见);恢复授权后看门狗会再走到这里
        guard AXIsProcessTrusted() else { return }

        if let tap = eventTap, CFMachPortIsValid(tap) {
            // 端口仍然有效:只是被系统禁用(Secure Input、超时等),重新启用即可
            if !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
                log("事件拦截曾被系统禁用,已重新启用(\(reason))")
            }
            return
        }

        // 端口已作废(睡眠/唤醒、显示器重配置),或此前从未装上(未授权):
        // 只能整体重建
        let hadTap = eventTap != nil
        if hadTap {
            log("事件拦截端口已失效,重建(\(reason))")
            uninstallEventTap()
        }
        resetState()
        if installEventTap(quiet: true) {
            log("事件拦截已重建(\(reason))")
            // 从"未授权/无 tap"变为可用:刷新菜单,去掉辅助功能授权提示项
            if !hadTap { setupStatusItem() }
        } else {
            log("事件拦截重建失败(\(reason)),等待下次体检重试")
        }
    }

    // 注:原先 1Hz 的「权限轮询」计时器已移除 —— 它既不持有也不失效,
    // 用户始终不授权时会永久跑满进程生命周期,且会反复重建菜单栏图标。
    // 授权检测与 tap 重建统一交给 5 秒一次的看门狗(ensureEventTapHealthy):
    // 它在授权恢复后会自行安装 tap,并调用 setupStatusItem() 刷新菜单。

    // MARK: Status item

    /// 定位 SwiftPM 资源 bundle 中的资源目录
    private func statusIconDirectory() -> URL? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("SlowQ_SlowQ.bundle/Contents/Resources"),
            Bundle(for: AppDelegate.self).resourceURL,
            Bundle.main.resourceURL,
        ].compactMap { $0 }
        for dir in candidates where FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("statusbar.png").path
        ) {
            return dir
        }
        return nil
    }

    /// 菜单栏图标:加载生成的 1x/2x 资源为多表示图。
    ///
    /// 1x 文件的像素尺寸就是逻辑点数,据此设置 size,避免被拉伸变形;
    /// 2x 作为 Retina 表示图由 AppKit 自动选用。缺失时回退系统 ⏳ 符号。
    ///
    /// 模板模式由 `statusIconTemplateOverride` 决定:未设置时**自动识别** ——
    /// 若图标本身是单色(如纯黑剪影),用模板模式(深色菜单栏自动变白);
    /// 有彩色信息才用彩色模式,避免黑色图标在深色菜单栏上隐形。
    private func loadStatusIcon() -> NSImage? {
        guard let dir = statusIconDirectory(),
              let data1x = try? Data(contentsOf: dir.appendingPathComponent("statusbar.png")),
              let rep1x = NSBitmapImageRep(data: data1x) else {
            return nil
        }
        let logicalSize = NSSize(width: rep1x.pixelsWide, height: rep1x.pixelsHigh)
        let image = NSImage(size: logicalSize)

        rep1x.size = logicalSize
        image.addRepresentation(rep1x)

        if let data2x = try? Data(contentsOf: dir.appendingPathComponent("statusbar@2x.png")),
           let rep2x = NSBitmapImageRep(data: data2x) {
            rep2x.size = logicalSize
            image.addRepresentation(rep2x)
        }

        image.isTemplate = statusIconTemplateOverride ?? isMonochrome(rep1x)
        return image
    }

    /// 判断图标是否为单色(所有不透明像素的 RGB 三通道差异都很小)
    private func isMonochrome(_ rep: NSBitmapImageRep) -> Bool {
        var sampled = 0
        var maxSpread: CGFloat = 0
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                guard let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.5 else { continue }
                let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
                let spread = max(r, max(g, b)) - min(r, min(g, b))
                maxSpread = max(maxSpread, spread)
                sampled += 1
            }
        }
        guard sampled > 0 else { return true } // 全透明 → 当单色处理
        return maxSpread < 0.12 // 阈值:明显有色才算彩色
    }

    /// 模板模式:默认**自动识别**(单色图标→模板模式,深色菜单栏自动变白;彩色图标→保留原色)。
    /// 隐藏的手动覆盖(菜单里不暴露,仅在需要时用终端调整):
    ///   defaults write com.slowq.app statusIconTemplate -bool true   # 强制单色
    ///   defaults write com.slowq.app statusIconTemplate -bool false  # 强制彩色
    ///   defaults delete com.slowq.app statusIconTemplate             # 回到自动(默认)
    private var statusIconTemplateOverride: Bool? {
        UserDefaults.standard.object(forKey: "statusIconTemplate") as? Bool
    }

    /// 供日志显示当前生效模式
    private func statusIconModeLabel() -> String {
        if let forced = statusIconTemplateOverride {
            return forced ? "单色(手动)" : "彩色(手动)"
        }
        return "自动"
    }

    private func setupStatusItem() {
        // 幂等:已存在则只刷新菜单,不重复创建(避免重试循环堆积菜单栏图标)
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }
        // 关键:系统会持久化状态栏项的可见性,隐藏过一次后新建的实例仍是隐藏的。
        // 显式置为可见,启动时才会有那个 10 秒"逃生窗口";之后由定时器再隐藏。
        statusItem.isVisible = true
        if let button = statusItem.button {
            if let icon = loadStatusIcon() {
                button.image = icon // 尺寸由资源自身决定,不强制缩放
                log("状态栏图标: \(Int(icon.size.width))x\(Int(icon.size.height))pt, 模式=\(statusIconModeLabel()), isTemplate=\(icon.isTemplate)")
            } else {
                button.image = NSImage(systemSymbolName: "hourglass", accessibilityDescription: "SlowQ")
            }
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self   // 打开菜单时取消"启动后自动隐藏"

        // 启动后的 10 秒逃生窗口:提示图标即将自动隐藏,打开菜单即可保留
        if autoHideTimer != nil {
            let hint = NSMenuItem(
                title: "⏱ 菜单栏图标将在启动 10 秒后隐藏(打开菜单即保留)",
                action: nil, keyEquivalent: ""
            )
            hint.isEnabled = false
            menu.addItem(hint)
            menu.addItem(.separator())
        }

        // ── 拦截开关 ──
        let toggle = NSMenuItem(
            title: enabled ? "停用(暂时不拦截 ⌘Q)" : "启用拦截 ⌘Q",
            action: #selector(toggleEnabled), keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        // ── 定时暂停:适合"接下来一段时间不想被拦"的场景,到点自动恢复 ──
        if let until = pauseUntil {
            let mins = max(1, Int(ceil(until.timeIntervalSinceNow / 60)))
            let info = NSMenuItem(title: "已暂停,还剩约 \(mins) 分钟", action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
            let resume = NSMenuItem(title: "立即恢复拦截", action: #selector(resumeNow), keyEquivalent: "")
            resume.target = self
            menu.addItem(resume)
        } else {
            let pauseTitle = NSMenuItem(title: "暂停拦截", action: nil, keyEquivalent: "")
            pauseTitle.isEnabled = false
            menu.addItem(pauseTitle)
            for mins in [5, 15, 60] {
                let item = NSMenuItem(title: "\(mins) 分钟", action: #selector(pauseFor(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = mins
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())

        // ── 按住时长 ──
        let title = NSMenuItem(title: "按住时长", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        for s in [0.5, 1.0, 2.0, 3.0, 5.0] {
            // 0.5 这类小数要保留一位,整数不带小数点
            let label = s == s.rounded() ? "\(Int(s))" : String(format: "%.1f", s)
            let item = NSMenuItem(
                title: "\(label) 秒\(abs(holdSeconds - s) < 0.01 ? " ✓" : "")",
                action: #selector(setHoldSeconds(_:)), keyEquivalent: ""
            )
            item.target = self
            item.representedObject = s
            menu.addItem(item)
        }
        menu.addItem(.separator())

        // ── 通用 ──
        let login = NSMenuItem(
            title: "登录时自动启动\(launchAtLoginEnabled ? " ✓" : "")",
            action: #selector(toggleLaunchAtLogin), keyEquivalent: ""
        )
        login.target = self
        menu.addItem(login)

        let hide = NSMenuItem(
            title: "隐藏菜单栏图标(再次打开应用可恢复)", action: #selector(hideStatusItem), keyEquivalent: ""
        )
        hide.target = self
        menu.addItem(hide)

        let about = NSMenuItem(
            title: "关于 慢Q (v\(appVersion))", action: #selector(showAbout), keyEquivalent: ""
        )
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())

        // 未授权时给出明确入口:重建后辅助功能授权会失效,需要重新勾选
        if !AXIsProcessTrusted() {
            let grant = NSMenuItem(
                title: "⚠️ 打开辅助功能设置(需授权后才能拦截 ⌘Q)",
                action: #selector(openAccessibilitySettings), keyEquivalent: ""
            )
            grant.target = self
            menu.addItem(grant)
            menu.addItem(.separator())
        }

        let quit = NSMenuItem(
            title: "退出 慢Q (⌥⌘Q)", action: #selector(quitSelf), keyEquivalent: "q"
        )
        quit.keyEquivalentModifierMask = [.command, .option]
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // MARK: 实用功能

    /// 当前应用版本(读 Info.plist)
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// 安排"启动后自动隐藏菜单栏图标"
    private func scheduleAutoHide(after seconds: TimeInterval) {
        autoHideTimer?.invalidate()
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.autoHideTimer = nil
            guard self.statusItemHidden else { return }
            self.statusItem.isVisible = false
            self.log("菜单栏图标已自动隐藏(重新启动应用可再次显示)")
        }
    }

    @objc private func hideStatusItem() {
        statusItemHidden = true
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        // 先弹提示再隐藏,让用户当场就知道怎么找回
        showToast("菜单栏图标已隐藏 · 再次打开 慢Q 即可恢复")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.statusItem.isVisible = false
        }
        log("菜单栏图标已隐藏(再次打开应用可恢复)")
    }

    /// 用户再次打开应用(双击 Finder / 启动台 / `open`)时,把菜单栏图标恢复出来。
    /// 这是「隐藏图标」唯一的、可发现的自救入口 —— 之前只靠"重启后 10 秒窗口",
    /// 但应用一直在后台运行,重新打开并不会重启进程,那个窗口根本不会触发。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // statusItem 是隐式解包可选(NSStatusItem!):此处若早于 setupStatusItem()
        // 被调用,直接解引用会崩溃,因此先判空并补建。
        guard let item = statusItem else {
            setupStatusItem()
            log("重新打开应用:菜单栏图标已补建")
            return false
        }
        if statusItemHidden || item.isVisible == false {
            statusItemHidden = false
            autoHideTimer?.invalidate()
            autoHideTimer = nil
            item.isVisible = true
            rebuildMenu()
            log("重新打开应用:菜单栏图标已恢复")
            showToast("菜单栏图标已恢复")
        }
        return false
    }

    /// 打开菜单即取消待执行的自动隐藏(用户显然还需要这个图标)
    func menuWillOpen(_ menu: NSMenu) {
        if autoHideTimer != nil {
            autoHideTimer?.invalidate()
            autoHideTimer = nil
            log("用户打开了菜单,取消自动隐藏")
        }
    }

    // ── 定时暂停 ──
    @objc private func pauseFor(_ sender: NSMenuItem) {
        guard let mins = sender.representedObject as? Int else { return }
        pauseUntil = Date().addingTimeInterval(TimeInterval(mins * 60))
        enabled = false
        pauseTimer?.invalidate()
        pauseTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            if let until = self.pauseUntil, until.timeIntervalSinceNow <= 0 {
                t.invalidate()
                self.resumeNow()
            } else {
                self.rebuildMenu()   // 刷新剩余时间
            }
        }
        log("已暂停拦截 \(mins) 分钟")
        rebuildMenu()
    }

    @objc private func resumeNow() {
        pauseUntil = nil
        pauseTimer?.invalidate()
        pauseTimer = nil
        enabled = true
        log("已恢复拦截")
        rebuildMenu()
    }

    // ── 登录时自动启动 ──
    private var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if launchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
                log("已关闭登录时自动启动")
            } else {
                try SMAppService.mainApp.register()
                log("已开启登录时自动启动")
            }
        } catch {
            log("设置登录项失败: \(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = launchAtLoginEnabled ? "无法关闭登录时自动启动" : "无法开启登录时自动启动"
            alert.informativeText = """
            \(error.localizedDescription)

            提示:该功能需要应用位于「应用程序」文件夹中(即 /Applications/SlowQ.app)。
            开发目录里的构建可能无法注册登录项。
            """
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
        rebuildMenu()
    }

    // ── 关于 ──
    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "慢Q (SlowQ) v\(appVersion)"
        alert.informativeText = """
        防误触退出助手 · 退一步,再确认。
        Slow down quitting.

        按住 ⌘Q 满设定时长才会退出应用,避免误触。

        GitHub: github.com/PandaBoby/SlowQ
        Gitee:  gitee.com/pandaboby/SlowQ
        """
        alert.addButton(withTitle: "打开 GitHub")
        alert.addButton(withTitle: "好")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "https://github.com/PandaBoby/SlowQ")!)
        }
    }

    /// 打开系统设置的辅助功能面板
    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        )
    }

    @objc private func toggleEnabled() {
        enabled.toggle()
        rebuildMenu()
    }

    @objc private func setHoldSeconds(_ sender: NSMenuItem) {
        if let s = sender.representedObject as? Double {
            holdSeconds = s
            UserDefaults.standard.set(s, forKey: "holdSeconds")
        }
        rebuildMenu()
    }

    @objc private func quitSelf() {
        NSApp.terminate(nil)
    }

    // MARK: Event tap

    // 保存 userInfo 指针以便释放
    private var userInfoPointer: UnsafeMutableRawPointer?

    /// - Parameter quiet: true 时失败不弹权限提示窗(用于轮询重试路径,避免每秒弹窗)
    private func installEventTap(quiet: Bool = false) -> Bool {
        // 幂等:仅在现有 tap 仍然健康时早退。
        // 不能只判 `eventTap != nil` —— 睡眠/唤醒后系统作废的是底层 Mach port,
        // CFMachPort 引用仍非 nil,只判非空会让所有恢复路径永远早退。
        if isEventTapHealthy { return true }
        if eventTap != nil { uninstallEventTap() }

        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let selfPtr = Unmanaged<AppDelegate>.passRetained(self).toOpaque()

        // Swift 闭包上下文指针
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            let me = Unmanaged<AppDelegate>.fromOpaque(refcon!).takeUnretainedValue()
            return me.handleEvent(proxy: proxy, type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: selfPtr
        ) else {
            // 失败路径:释放上面 passRetained 的引用,避免反复启动时泄漏
            Unmanaged<AppDelegate>.fromOpaque(selfPtr).release()
            log("event tap 创建失败(权限不足)")
            if !quiet {
                showPermissionsAlert()
            }
            return false
        }

        userInfoPointer = selfPtr
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        log("event tap 安装成功")
        return true
    }

    private func uninstallEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
        if let ptr = userInfoPointer {
            Unmanaged<AppDelegate>.fromOpaque(ptr).release()
            userInfoPointer = nil
        }
    }

    private func showPermissionsAlert() {
        let alert = NSAlert()
        alert.messageText = "需要辅助功能权限"
        alert.informativeText =
            "SlowQ 需要在「系统设置 → 隐私与安全性 → 辅助功能」中被勾选,才能拦截所有应用的 ⌘Q。请勾选后重新启动 SlowQ。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "好")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            )
        }
    }

    // MARK: Event handling

    /// 合成 ⌘Q 的标记值:写入 eventSourceUserData,用于让自家 tap
    /// 识别并放行自己投递的合成事件(见 sendQuitToActiveApp)
    private static let syntheticQuitTag: Int64 = 0x536C_6F77_51 // "SlowQ"

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
            // 暂停窗口内不干预(否则会提前重开 tap、破坏暂停契约);
            // 端口已失效时 tapEnable 本身也无效,交给看门狗重建。
            if !eventTapIsPaused, let tap = eventTap, CFMachPortIsValid(tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard enabled else { return Unmanaged.passUnretained(event) }

        let flags = event.flags
        let cmd = flags.contains(.maskCommand)
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        // 自家投递的合成 ⌘Q(带标记)直接放行,避免 tap 开启状态下被自己再拦
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticQuitTag {
            return Unmanaged.passUnretained(event)
        }

        // 隐私:只记录 ⌘Q 相关事件,不落盘其他按键序列
        let isQEvent = keyCode == 12

        switch type {
        case .flagsChanged:
            if isQEvent || holding { log("flagsChanged cmd=\(cmd)") }
            // ⌘ 松开时,如果还没达到时长,取消本次退出
            if holding && !cmd {
                cancelHold()
            }
            return Unmanaged.passUnretained(event)

        case .keyDown:
            if isQEvent && cmd {
                log("keyDown code=12 cmd=true holding=\(holding) fired=\(fired)")
                // 拦截 Cmd+Q(keycode 12 = Q)。
                // 关键:按住期间系统会自动重复 keyDown(key repeat),
                // 只要处于 holding 状态(无论 fired 与否)一律吞掉。
                if holding { return nil }
                if pausedForSyntheticQuit { return nil } // 暂停窗口内物理 ⌘Q 也不放行
                beginHold()
                return nil
            }
            return Unmanaged.passUnretained(event)

        case .keyUp:
            if isQEvent && cmd {
                log("keyUp code=12 cmd=true holding=\(holding) fired=\(fired)")
                if holding {
                    endHold()
                    return nil // 松开时不放行 keyUp(避免应用收到孤立的 keyUp)
                }
            }
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    // MARK: Logging(默认关闭,避免拖慢全局键盘事件与记录按键序列)

    /// 调试日志开关:`defaults write com.slowq.app debugLog -bool true`
    private var debugLogEnabled: Bool {
        UserDefaults.standard.bool(forKey: "debugLog")
    }

    private func log(_ s: String) {
        guard debugLogEnabled else { return }
        let line = "\(Date().timeIntervalSince1970) \(s)\n"
        let data = line.data(using: .utf8)!
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.flushLog(data)
        }
    }

    private let logQueue = DispatchQueue(label: "com.slowq.app.log")
    private func flushLog(_ data: Data) {
        logQueue.sync {
            let path = NSHomeDirectory() + "/Library/Logs/SlowQ.log"
            let fm = FileManager.default
            if !fm.fileExists(atPath: path) {
                guard fm.createFile(atPath: path, contents: nil) else {
                    // 兜底路径也走追加,避免覆盖
                    let fallback = URL(fileURLWithPath: "/tmp/slowq-fallback.log")
                    if let fh = FileHandle(forWritingAtPath: fallback.path) {
                        defer { try? fh.close() }
                        fh.seekToEndOfFile()
                        fh.write(data)
                    }
                    return
                }
            }
            guard let fh = FileHandle(forWritingAtPath: path) else { return }
            defer { try? fh.close() }
            fh.seekToEndOfFile()
            fh.write(data)
        }
    }

    private func beginHold() {
        holding = true
        fired = false
        holdStartTime = CACurrentMediaTime()
        showHUD()
        // 定时检查是否达到时长。存为属性,以便睡眠/复位时能立即作废 ——
        // 否则跨睡眠的残留计时会把一次早已放弃的按住兑现成真实退出。
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            guard self.holding else { t.invalidate(); return }
            let elapsed = CACurrentMediaTime() - self.holdStartTime
            self.updateHUD(elapsed: elapsed)
            if elapsed >= self.holdSeconds {
                t.invalidate()
                self.holdTimer = nil
                self.fireQuit()
            }
        }
    }

    private func fireQuit() {
        fired = true
        hideHUD()
        // 真正退出:向最前面的应用发送 Cmd+Q,但此刻要先暂时停止拦截
        eventTapIsPaused = true
        // 检测当前按下的修饰键里是否仍按着 ⌘
        let stillCmd = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Command))
        if stillCmd {
            // 等用户松开 ⌘ 后再放行一次合成 ⌘Q,否则再触发拦截
            waitForCommandReleaseThenSend()
        } else {
            sendQuitToActiveApp()
        }
    }

    /// 暂停状态(单一来源):暂停窗口内不放行**物理** ⌘Q。
    /// 赋值处:fireQuit 置 true / sendQuitToActiveApp 完成后置 false。
    ///
    /// 注意:这里**不能**物理禁用 tap(CGEvent.tapEnable(false))。
    /// 禁用 tap 期间,按住产生的 ⌘Q keyDown 系统按键重复不再经过回调,
    /// 会原样漏给前台应用,把 App A 退掉;之后轮询检测到 ⌘ 松开,
    /// 合成 ⌘Q 又投给已接管前台的 App B —— 一次按满连退两个应用。
    /// tap 保持开启,由 handleEvent 的 pausedForSyntheticQuit 分支吞掉物理 ⌘Q
    /// 即可;合成事件本身走 postToPid 的 per-PID 通道、不经会话 tap,不会被再拦。
    private var eventTapIsPaused = false {
        didSet {
            guard eventTapIsPaused != oldValue else { return }
            // 记录进入暂停的时刻,供看门狗对暂停窗口加硬超时
            pausedAt = eventTapIsPaused ? Date() : nil
        }
    }

    /// handleEvent 层兜底:暂停窗口内到达的物理 ⌘Q 也不放行
    private var pausedForSyntheticQuit: Bool { eventTapIsPaused }

    private func waitForCommandReleaseThenSend() {
        // 轮询等 ⌘ 松开,然后发送合成 ⌘Q。
        // 必须带硬超时:若 ⌘ 的 keyUp 被睡眠转换吞掉、或唤醒后键态被 latch,
        // 没有超时的轮询会让 eventTapIsPaused 永久为 true —— tap 从此物理禁用、
        // ⌘Q 不再被拦截,而且没有任何恢复路径(与本次故障同症状)。
        // 超时语义是**放弃**本次合成退出:此时 ⌘ 键态可疑(latch),强行投递 ⌘Q
        // 会退出用户未必想退的应用;看门狗的 3s 强制复位作为最后兜底。
        commandReleaseTimer?.invalidate()
        let deadline = Date().addingTimeInterval(1.5)
        commandReleaseTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            let down = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Command))
            if !down {
                t.invalidate()
                self.commandReleaseTimer = nil
                self.sendQuitToActiveApp()
            } else if Date() >= deadline {
                t.invalidate()
                self.commandReleaseTimer = nil
                self.log("等待 ⌘ 松开超时,放弃本次合成退出并复位暂停状态")
                self.eventTapIsPaused = false
                self.resetState()
            }
        }
    }

    private func sendQuitToActiveApp() {
        // 找到当前最前面的应用并发送 ⌘Q
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            let src = CGEventSource(stateID: .combinedSessionState)
            let keyDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_Q), keyDown: true)
            keyDown?.flags = .maskCommand
            // 烙上标记:tap 不再物理禁用,若这条合成 ⌘Q 经过自家 tap,
            // 靠标记识别并放行,避免被自己再拦一次
            keyDown?.setIntegerValueField(.eventSourceUserData, value: Self.syntheticQuitTag)
            keyDown?.postToPid(frontApp.processIdentifier)
            let keyUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_Q), keyDown: false)
            keyUp?.flags = .maskCommand
            keyUp?.setIntegerValueField(.eventSourceUserData, value: Self.syntheticQuitTag)
            keyUp?.postToPid(frontApp.processIdentifier)
        }
        // 恢复拦截。合成事件走 per-PID 通道、不经会话 tap,
        // 因此 tap 保持开启也不会再次拦截到这条合成 ⌘Q(详见 eventTapIsPaused 注释)。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            self.eventTapIsPaused = false
            self.resetState()
        }
    }

    private func cancelHold() {
        guard holding, !fired else { return }
        holding = false
        hideHUD()
    }

    private func endHold() {
        holding = false
        hideHUD()
    }

    private func resetState() {
        holding = false
        fired = false
        holdTimer?.invalidate()
        holdTimer = nil
        hideHUD()
    }
}

// MARK: - HUD Overlay

final class OverlayWindow: NSWindow {
    let progress = ProgressIndicatorView()
    static let preferredSize = CGSize(width: 240, height: 260)

    init() {
        let size = Self.preferredSize
        let frame = Self.centeredFrame()

        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered, defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hasShadow = false // 自绘阴影

        progress.frame = NSRect(origin: .zero, size: size)
        contentView = progress
    }

    /// 按键盘焦点所在屏幕计算居中 frame。
    /// NSScreen.main = 拦截触发时用户正在使用的屏;窗口是 stationary 的,
    /// 不会跟随显示器变化移动,因此每次显示前都要重算。
    static func centeredFrame() -> NSRect {
        let size = preferredSize
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2,
            width: size.width, height: size.height
        )
    }

    /// 每次显示前调用:把窗口摆回当前焦点屏幕的中心。
    /// 进程长期运行中,合盖唤醒 / 外接屏插拔 / 主屏切换都会让旧坐标
    /// 落到看不见的屏幕上 —— HUD 会"消失"而拦截功能一切正常。
    func recentreOnCurrentScreen() {
        setFrame(Self.centeredFrame(), display: false)
    }
}

/// 弱引用盒子,供 C 回调上下文安全持有 Swift 对象
final class WeakBox {
    weak var value: ProgressIndicatorView?
    init(_ v: ProgressIndicatorView?) { value = v }
}

final class ProgressIndicatorView: NSView {
    var elapsed: Double = 0
    var total: Double = 3

    // 动画状态
    private var displayLink: CVDisplayLink?
    // 回调上下文盒子:与 view 同生命周期(仅 deinit 释放)。
    // 不在 stopAnimation 里释放 —— CVDisplayLinkStop 返回不保证在途回调
    // 已结束,立刻 release 会让回调线程解引用已释放内存。
    private var displayLinkBox: UnsafeMutableRawPointer?
    private var pulsePhase: CGFloat = 0

    // 图标:一次着色缓存,draw 每帧直接使用
    private lazy var tintedIcon: NSImage? = {
        guard let base = NSImage(systemSymbolName: "keyboard.command", accessibilityDescription: "Command")
            ?? NSImage(systemSymbolName: "command", accessibilityDescription: "Command")
            ?? NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Command")
        else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        guard let sized = base.withSymbolConfiguration(config) else { return nil }
        // 防御性转换而非 `as!`:此处失败会直接崩溃,而这条图标着色路径
        // 历史上就出过一次强制解包崩溃(Swift runtime failure: unexpectedly
        // found nil)。失败时优雅降级为不画图标,而不是让 App 挂掉。
        guard let tinted = sized.copy() as? NSImage else { return nil }
        tinted.lockFocus()
        NSColor.white.withAlphaComponent(0.85).set()
        NSRect(origin: .zero, size: sized.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        return tinted
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    /// 显示时启动动画循环,隐藏时停止(避免常驻空转)
    func startAnimation() {
        stopAnimation()
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else { return }
        displayLink = link
        // 弱引用盒子:回调不 retain view,且与 view 同生命周期(见 deinit)。
        // 每次启动都把盒子的 weak 引用拨回 self —— view 从未重建时这是
        // 幂等的,重建时则修复悬空引用。
        if displayLinkBox == nil {
            displayLinkBox = Unmanaged.passRetained(WeakBox(self)).toOpaque()
        } else {
            Unmanaged<WeakBox>.fromOpaque(displayLinkBox!).takeUnretainedValue().value = self
        }
        let opaque = displayLinkBox!
        CVDisplayLinkSetOutputCallback(link, { _, _, _, _, flagsOut, ctx in
            let box = Unmanaged<WeakBox>.fromOpaque(ctx!).takeUnretainedValue()
            if let view = box.value {
                DispatchQueue.main.async { view.tick() }
            }
            flagsOut.pointee = 0
            return kCVReturnSuccess
        }, opaque)
        CVDisplayLinkStart(link)
    }

    func stopAnimation() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
        }
        // 只停不释放:box 的释放统一在 deinit。link 置空即可,
        // 下次 startAnimation 会走创建分支,不会复用已死的 link。
        displayLink = nil
    }

    /// 显示器配置变化(含唤醒)后重连动画,避免进度环冻结在旧 link 上
    func refreshAnimationIfVisible() {
        guard window?.isVisible == true else { return }
        stopAnimation()
        startAnimation()
    }

    @objc private func tick() {
        guard let window = window, window.isVisible else { return }
        pulsePhase += 0.08
        needsDisplay = true
    }

    deinit {
        if let link = displayLink {
            CVDisplayLinkStop(link)
        }
        // 停止后仍有在途回调的可能,推迟到下一个 runloop tick 再释放,
        // 避免回调线程解引用已释放的盒子
        if let opaque = displayLinkBox {
            DispatchQueue.global(qos: .utility).async {
                Unmanaged<WeakBox>.fromOpaque(opaque).release()
            }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            // 入场缩放动画
            layer?.removeAllAnimations()
            let anim = CASpringAnimation(keyPath: "transform.scale")
            anim.fromValue = 0.7
            anim.toValue = 1.0
            anim.damping = 14
            anim.mass = 0.9
            anim.stiffness = 190
            anim.duration = 0.45
            layer?.add(anim, forKey: "appear")
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.35
                self.animator().alphaValue = 1.0
            })
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let inset: CGFloat = 20
        let cardRect = bounds.insetBy(dx: 8, dy: 8)
        let ringRect = bounds.insetBy(dx: inset + 8, dy: inset + 42)
        let center = CGPoint(x: bounds.midX, y: bounds.midY + 18)
        let radius = min(ringRect.width, ringRect.height) / 2
        let frac = total > 0 ? min(1, elapsed / total) : 0

        // ── 卡片背景:毛玻璃质感(分层绘制)──
        // 外圈柔和阴影
        let shadowColor = NSColor(calibratedWhite: 0, alpha: 0.35)
        shadowColor.setFill()
        let shadowRect = cardRect.insetBy(dx: -6, dy: -6)
        let shadowPath = NSBezierPath(roundedRect: shadowRect, xRadius: 36, yRadius: 36)
        shadowPath.fill()

        // 卡片主体
        let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: 32, yRadius: 32)
        NSColor(calibratedWhite: 0.08, alpha: 0.82).setFill()
        cardPath.fill()
        // 顶部高光渐变(玻璃感)
        let gradient = NSGradient(
            starting: NSColor(white: 1, alpha: 0.14),
            ending: NSColor(white: 1, alpha: 0.02)
        )
        gradient?.draw(in: cardPath, angle: -90)

        // ── 圆环 ──
        let ringWidth: CGFloat = 10

        // 快完成时的脉冲光晕(>70%)
        if frac > 0.7 {
            let pulse = (sin(pulsePhase) + 1) / 2 // 0..1
            let glowAlpha = 0.10 + 0.18 * pulse * CGFloat((frac - 0.7) / 0.3)
            NSColor.systemRed.withAlphaComponent(glowAlpha).setFill()
            let glowRect = NSRect(
                x: center.x - radius - 18, y: center.y - radius - 18,
                width: (radius + 18) * 2, height: (radius + 18) * 2
            )
            NSBezierPath(ovalIn: glowRect).fill()
        }

        // 背景轨道
        NSColor.white.withAlphaComponent(0.14).setStroke()
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = ringWidth
        track.stroke()

        // 进度弧:蓝→红渐变,随进度变化
        if frac > 0.001 {
            let startAngle: CGFloat = 90
            let endAngle: CGFloat = 90 - 360 * frac
            let arc = NSBezierPath()
            arc.appendArc(
                withCenter: center, radius: radius,
                startAngle: startAngle, endAngle: endAngle, clockwise: true
            )
            arc.lineWidth = ringWidth
            arc.lineCapStyle = .round

            let t = CGFloat(frac)
            let ringColor = NSColor(
                calibratedRed: 0.22 + 0.66 * t, green: 0.55 - 0.40 * t, blue: 1.0 - 0.85 * t, alpha: 1.0
            )
            ringColor.setStroke()
            arc.stroke()
        }

        // ── 中心:命令图标 + 倒计时数字 ──
        // 着色图标已缓存(lazy 一次),draw 直接绘制;缺失时优雅降级
        if let icon = tintedIcon {
            let iconSize = icon.size
            icon.draw(
                in: NSRect(
                    x: center.x - iconSize.width / 2,
                    y: center.y + 26,
                    width: iconSize.width, height: iconSize.height
                )
            )
        }

        let remain = max(0, total - elapsed)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let numAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 40, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: para,
        ]
        (String(format: "%.1f", remain) as NSString).draw(
            in: NSRect(x: 0, y: center.y - 40, width: bounds.width, height: 48),
            withAttributes: numAttrs
        )

        // ── 底部标签 ──
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.75),
            .paragraphStyle: para,
        ]
        let label = frac >= 1 ? "松开以退出" : "按住 ⌘Q 退出"
        (label as NSString).draw(
            in: NSRect(x: 0, y: cardRect.minY + 22, width: bounds.width, height: 20),
            withAttributes: labelAttrs
        )
    }

    func update(elapsed: Double, total: Double) {
        self.elapsed = elapsed
        self.total = total
        needsDisplay = true
    }
}

// MARK: - 轻提示(Toast)

/// 短暂的屏幕提示条:用于"图标已隐藏/已恢复"这类一次性反馈。
/// 不依赖通知权限,也不抢焦点(非激活面板)。
///
/// 位置固定在**屏幕顶部**(菜单栏下方)并水平居中;卡片宽度按文字自适应,
/// 因此任何长度的提示都是居中的、不会被截断。
final class ToastWindow: NSWindow {
    private let label = NSTextField(labelWithString: "")

    /// 距菜单栏下沿的间距(点)
    private static let topMargin: CGFloat = 10
    /// 卡片内边距与高度
    private static let hPad: CGFloat = 22
    private static let height: CGFloat = 46

    init(text: String) {
        let font = NSFont.systemFont(ofSize: 14, weight: .medium)
        let textWidth = (text as NSString)
            .size(withAttributes: [.font: font]).width
        // 宽度自适应内容,并夹在合理区间内
        let w = min(max(textWidth + Self.hPad * 2, 240), 680)
        let h = Self.height

        // 顶部居中:visibleFrame 已排除菜单栏,取其 maxY 再向下留出间距
        let screen = NSScreen.main ?? NSScreen.screens.first
        let vf = screen?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let originX = vf.midX - w / 2
        let originY = vf.maxY - h - Self.topMargin

        super.init(
            contentRect: NSRect(x: originX, y: originY, width: w, height: h),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hasShadow = false

        let card = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 0.90).cgColor
        card.layer?.cornerRadius = h / 2   // 胶囊形,顶部提示更轻盈
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.14).cgColor

        label.stringValue = text
        label.alignment = .center          // 文字水平居中
        label.font = font
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: Self.hPad, y: (h - 19) / 2, width: w - Self.hPad * 2, height: 19)
        card.addSubview(label)
        contentView = card
    }
}

extension AppDelegate {
    /// 弹出一条提示,2.6 秒后自动淡出
    func showToast(_ text: String) {
        toastWindow?.orderOut(nil)
        let w = ToastWindow(text: text)
        if let scr = NSScreen.main {
            let f = w.frame
            let centered = abs(f.midX - scr.visibleFrame.midX) < 0.5
            let atTop = abs(f.maxY - (scr.visibleFrame.maxY - 10)) < 0.5
            self.log("提示条「\(text)」frame=\(Int(f.width))x\(Int(f.height)) @(\(Int(f.minX)),\(Int(f.minY))) 居中=\(centered) 顶部=\(atTop)")
        }
        toastWindow = w
        w.alphaValue = 0
        w.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            w.animator().alphaValue = 1
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self, weak w] in
            guard let w else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                w.animator().alphaValue = 0
            }, completionHandler: {
                w.orderOut(nil)
                if self?.toastWindow === w { self?.toastWindow = nil }
            })
        }
    }

    func showHUD() {
        hudGeneration += 1   // 作废所有在途的淡出回调,防止它们 orderOut 新一轮 HUD
        if hudWindow == nil { hudWindow = OverlayWindow() }
        // 窗口是 stationary 的,坐标停留在创建(或上次重摆)时的屏幕上;
        // 长期运行中显示器配置一变就再也看不见。每次显示都重摆回焦点屏。
        hudWindow?.recentreOnCurrentScreen()
        hudWindow?.progress.total = holdSeconds
        hudWindow?.progress.elapsed = 0
        hudWindow?.alphaValue = 0
        hudWindow?.orderFrontRegardless()
        if let w = hudWindow, let scr = NSScreen.main {
            log("HUD 显示 frame=\(Int(w.frame.width))x\(Int(w.frame.height)) @(\(Int(w.frame.minX)),\(Int(w.frame.minY))) 屏幕=\(Int(scr.frame.width))x\(Int(scr.frame.height)) @(\(Int(scr.frame.minX)),\(Int(scr.frame.minY))) 居中=\(abs(w.frame.midX - scr.frame.midX) < 0.5 && abs(w.frame.midY - scr.frame.midY) < 0.5)")
        }
        // 每次显示都重建动画:displayLink 绑定创建时的显示器配置,
        // 长时间运行/睡眠后可能已静默失效,复用会导致进度环永久冻结
        hudWindow?.progress.stopAnimation()
        hudWindow?.progress.startAnimation() // 显示时才开启动画循环
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            hudWindow?.animator().alphaValue = 1.0
        })
    }

    func updateHUD(elapsed: Double) {
        hudWindow?.progress.update(elapsed: elapsed, total: holdSeconds)
    }

    func hideHUD() {
        guard let w = hudWindow, w.isVisible else { return }
        hudGeneration += 1   // 本次隐藏的代数;回调触发时若代数已变,说明期间又 showHUD 了
        let gen = hudGeneration
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            w.animator().alphaValue = 0
        }, completionHandler: {
            // 竞态保护:0.15s 淡出期间用户可能再次按下 ⌘Q 触发了新的 showHUD,
            // 此时这个迟到的回调不能把新一轮 HUD orderOut 掉(否则动画"消失")
            guard self.hudGeneration == gen else { return }
            w.orderOut(nil)
            w.alphaValue = 1
            w.progress.stopAnimation() // 隐藏即停止空转
        })
    }
}
