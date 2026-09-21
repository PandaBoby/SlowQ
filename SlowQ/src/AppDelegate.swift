import Cocoa
import Carbon.HIToolbox
import ApplicationServices

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // 按住阈值(秒),可在菜单中调节
    private var holdSeconds: Double = 3.0
    private var enabled = true

    // 状态机
    private var holding = false
    private var holdStartTime: CFTimeInterval = 0
    private var fired = false // 本轮是否已放行/执行退出

    private var hudWindow: OverlayWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("启动")
        holdSeconds = UserDefaults.standard.double(forKey: "holdSeconds")
        if holdSeconds <= 0 { holdSeconds = 3.0 }

        // 主动检查辅助功能权限
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                as CFDictionary
        )
        if !trusted {
            log("未获得辅助功能权限,等待授权")
            // tap 装不上时 installEventTap 里也会弹窗,这里等待授权后自动重试
            pollForPermission()
            return
        }
        log("辅助功能权限 OK")

        setupStatusItem()
        installEventTap()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.uninstallEventTap()
        }
    }

    /// 授权成功前每秒轮询,一旦授权立即安装 tap 并显示菜单
    private func pollForPermission() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            if AXIsProcessTrusted() {
                t.invalidate()
                self.log("权限已授予,安装事件拦截")
                self.setupStatusItem()
                self.installEventTap()
                NotificationCenter.default.addObserver(
                    forName: NSApplication.willTerminateNotification,
                    object: nil, queue: .main
                ) { [weak self] _ in self?.uninstallEventTap() }
            }
        }
    }

    // MARK: Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "hourglass", accessibilityDescription: "SlowQ")
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let toggle = NSMenuItem(
            title: enabled ? "停用(暂时不拦截 ⌘Q)" : "启用拦截 ⌘Q",
            action: #selector(toggleEnabled), keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())

        let title = NSMenuItem(title: "按住时长", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        for s in [1.0, 2.0, 3.0, 5.0] {
            let item = NSMenuItem(
                title: "\(Int(s)) 秒\(abs(holdSeconds - s) < 0.01 ? " ✓" : "")",
                action: #selector(setHoldSeconds(_:)), keyEquivalent: ""
            )
            item.target = self
            item.representedObject = s
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "退出 SlowQ (⌥⌘Q)", action: #selector(quitSelf), keyEquivalent: "q"
        )
        quit.keyEquivalentModifierMask = [.command, .option]
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
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

    private func installEventTap() {
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let selfPtr = Unmanaged<AppDelegate>.passRetained(self).toOpaque()
        userInfoPointer = selfPtr

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
            log("event tap 创建失败(权限不足)")
            showPermissionsAlert()
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        log("event tap 安装成功")
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

    private func keyCode(of event: CGEvent) -> Int64 {
        event.getIntegerValueField(.keyboardEventKeycode)
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passRetained(event)
        }

        guard enabled else { return Unmanaged.passRetained(event) }

        let flags = event.flags
        let cmd = flags.contains(.maskCommand)
        let keyCode = keyCode(of: event)

        switch type {
        case .flagsChanged:
            log("flagsChanged cmd=\(cmd)")
            // ⌘ 松开时,如果还没达到时长,取消本次退出
            if holding && !cmd {
                cancelHold()
            }
            return Unmanaged.passRetained(event)

        case .keyDown:
            log("keyDown code=\(keyCode) cmd=\(cmd) holding=\(holding) fired=\(fired)")
            // 拦截 Cmd+Q(keycode 12 = Q)。
            // 关键:按住期间系统会自动重复 keyDown(key repeat),
            // 只要处于 holding 状态(无论 fired 与否)一律吞掉。
            if cmd && keyCode == 12 && holding {
                return nil
            }
            if cmd && keyCode == 12 && !holding {
                beginHold()
                return nil // 吞掉
            }
            return Unmanaged.passRetained(event)

        case .keyUp:
            log("keyUp code=\(keyCode) cmd=\(cmd) holding=\(holding) fired=\(fired)")
            if cmd && keyCode == 12 && holding {
                endHold()
                return nil // 松开时不放行 keyUp(避免应用收到孤立的 keyUp)
            }
            return Unmanaged.passRetained(event)

        default:
            return Unmanaged.passRetained(event)
        }
    }

    private func log(_ s: String) {
        let line = "\(Date().timeIntervalSince1970)) \(s)\n"
        let path = NSHomeDirectory() + "/Library/Logs/SlowQ.log"
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: nil)
        }
        guard let fh = FileHandle(forWritingAtPath: path) else {
            try? line.data(using: .utf8)!.write(to: URL(fileURLWithPath: "/tmp/slowq-fallback.log"), options: .atomic)
            return
        }
        fh.seekToEndOfFile()
        fh.write(line.data(using: .utf8)!)
        try? fh.close()
    }

    private func beginHold() {
        holding = true
        fired = false
        holdStartTime = CACurrentMediaTime()
        showHUD()
        // 定时检查是否达到时长
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            guard self.holding else { t.invalidate(); return }
            let elapsed = CACurrentMediaTime() - self.holdStartTime
            self.updateHUD(elapsed: elapsed)
            if elapsed >= self.holdSeconds {
                t.invalidate()
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

    private var eventTapIsPaused = false {
        didSet {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: !eventTapIsPaused)
            }
        }
    }

    private func waitForCommandReleaseThenSend() {
        // 轮询等 ⌘ 松开,然后发送合成 ⌘Q
        Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            let down = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Command))
            if !down {
                t.invalidate()
                self.sendQuitToActiveApp()
            }
        }
    }

    private func sendQuitToActiveApp() {
        // 找到当前最前面的应用并发送 ⌘Q
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            let src = CGEventSource(stateID: .combinedSessionState)
            let keyDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_Q), keyDown: true)
            keyDown?.flags = .maskCommand
            keyDown?.postToPid(frontApp.processIdentifier)
            let keyUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_Q), keyDown: false)
            keyUp?.flags = .maskCommand
            keyUp?.postToPid(frontApp.processIdentifier)
        }
        // 恢复拦截
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.eventTapIsPaused = false
            self?.resetState()
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
        hideHUD()
    }
}

// MARK: - HUD Overlay

final class OverlayWindow: NSWindow {
    let progress = ProgressIndicatorView()

    init() {
        let size = CGSize(width: 240, height: 260)
        // 显示在当前鼠标所在屏幕(拦截触发时用户焦点所在处)
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.midY - size.height / 2

        super.init(
            contentRect: NSRect(origin: CGPoint(x: x, y: y), size: size),
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
    private var pulsePhase: CGFloat = 0
    private var appeared = false

    // 图标(用 SF Symbols 渲染成图片)
    private lazy var symbolImage: NSImage? = {
        let config = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        let base = NSImage(systemSymbolName: "keyboard.command", accessibilityDescription: "Command")
            ?? NSImage(systemSymbolName: "command", accessibilityDescription: "Command")
            ?? NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Command")
        return base?.withSymbolConfiguration(config)
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // 允许隐式动画
        animatorProxy()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func animatorProxy() {
        // CVDisplayLink 驱动平滑动画(每帧重绘进度环/脉冲)
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        displayLink = link
        if let link {
            // 弱上下文:不 retain view,回调里校验存活,避免野指针/过度释放
            weak var weakSelf = self
            let opaque = Unmanaged.passRetained(WeakBox(weakSelf)).toOpaque()
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
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            appeared = true
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
            // 位置以 layer 锚点居中需要 transform;直接用 NSAnimationContext
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
        // SF Symbol 模板图,手动着色;图标缺失时优雅降级(不绘制)
        if let symbol = symbolImage {
            let tinted = symbol.copy() as! NSImage
            tinted.lockFocus()
            NSColor.white.withAlphaComponent(0.85).set()
            NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            let iconSize = symbol.size
            tinted.draw(
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

extension AppDelegate {
    func showHUD() {
        if hudWindow == nil { hudWindow = OverlayWindow() }
        hudWindow?.progress.total = holdSeconds
        hudWindow?.progress.elapsed = 0
        hudWindow?.alphaValue = 0
        hudWindow?.orderFrontRegardless()
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
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            w.animator().alphaValue = 0
        }, completionHandler: {
            w.orderOut(nil)
            w.alphaValue = 1
        })
    }
}
