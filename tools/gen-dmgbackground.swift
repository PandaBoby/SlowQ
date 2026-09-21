// gen-dmgbackground.swift — 生成 DMG 安装窗口的背景图
//
// 用法: swift tools/gen-dmgbackground.swift <输出目录> [宽pt] [高pt] [logo图路径] [像素倍率]
//
// 输出单个 background.png,像素尺寸 = 设计点数 × 倍率(默认 2)。
//
// 为什么直接输出 2x 像素而不是配置 background@2x.png:
//   实测 Finder 会把背景图**等比缩放到窗口大小**,并不按 @2x 命名去挑图 —— 只提供 1x 图时
//   它在 Retina 上被放大 2 倍,文字发虚;直接给 2x 像素的图,缩放后正好 1:1 映射到屏幕像素,
//   边缘对比度实测翻倍。
//
// 布局与 tools/make-dmg.sh 里设置的窗口尺寸、图标坐标保持一致 —— 改动布局时两边都要同步。
//
// 设计:顶部品牌横幅(logo + 名称 + 中英副标题)、中部拖拽箭头、
// 底部中英双语安装说明与首次打开的 Gatekeeper 处理提示。
//
// 坐标系说明:AppKit 位图上下文原点在左下,而设计稿习惯"自上而下"。
// 这里统一用 topY 书写并按 `H - topY - height` 换算,**不使用翻转 transform** ——
// 手动翻转会让 NSAttributedString 的文字上下颠倒。

import AppKit

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("用法: swift tools/gen-dmgbackground.swift <输出目录> [宽] [高]")
    exit(1)
}
let outDir = args[1]
let W: CGFloat = args.count >= 3 ? (Double(args[2]).map { CGFloat($0) } ?? 680) : 680
let H: CGFloat = args.count >= 4 ? (Double(args[3]).map { CGFloat($0) } ?? 520) : 520
/// 横幅里用的 logo 图(默认取当前目录下的 SlowQ/SlowQ.png)
let logoPath = args.count >= 5
    ? args[4]
    : (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent("SlowQ/SlowQ.png")
/// 输出像素倍率:2 = Retina 上 1:1 映射
let outScale: CGFloat = args.count >= 6 ? (Double(args[5]).map { CGFloat($0) } ?? 2) : 2

// ── 配色 ──
let bannerTop = NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.22, alpha: 1)
let bannerBottom = NSColor(calibratedRed: 0.25, green: 0.28, blue: 0.34, alpha: 1)
let pageTop = NSColor(calibratedRed: 0.99, green: 0.99, blue: 1.00, alpha: 1)
let pageBottom = NSColor(calibratedRed: 0.93, green: 0.94, blue: 0.96, alpha: 1)
let textPrimary = NSColor(calibratedWhite: 0.09, alpha: 1)
let textSecondary = NSColor(calibratedWhite: 0.27, alpha: 1)
let arrowColor = NSColor(calibratedWhite: 0.60, alpha: 1)

let bannerH: CGFloat = 104
/// 设计稿 topY(自上而下) → 位图坐标(自下而上)的矩形
func rect(topY: CGFloat, height: CGFloat, x: CGFloat = 0, width: CGFloat = W) -> NSRect {
    NSRect(x: x, y: H - topY - height, width: width, height: height)
}

/// 以 topY 为文字顶部绘制一行,返回其高度
@discardableResult
func drawText(_ text: String, topY: CGFloat, font: NSFont, color: NSColor,
              align: NSTextAlignment = .center, x: CGFloat = 0, width: CGFloat = W) -> CGFloat {
    let para = NSMutableParagraphStyle()
    para.alignment = align
    para.lineBreakMode = .byTruncatingTail
    let s = NSAttributedString(string: text, attributes: [
        .font: font, .foregroundColor: color, .paragraphStyle: para,
    ])
    let h = ceil(s.size().height)
    s.draw(in: rect(topY: topY, height: h, x: x, width: width))
    return h
}

func render(scale: CGFloat) -> NSBitmapImageRep? {
    let pw = Int(W * scale), ph = Int(H * scale)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: ph,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: W, height: H)

    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    ctx.shouldAntialias = true

    // ── 页面背景:浅色纵向渐变 ──
    NSGradient(starting: pageBottom, ending: pageTop)?
        .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

    // ── 顶部品牌横幅 ──
    let bannerRect = rect(topY: 0, height: bannerH)
    NSGradient(starting: bannerBottom, ending: bannerTop)?
        .draw(in: bannerRect, angle: -90)
    NSColor(calibratedWhite: 1, alpha: 0.10).setFill()
    NSRect(x: 0, y: bannerRect.minY, width: W, height: 1).fill()

    // 横幅内 logo(深色底上用白色版):按内容包围盒等比绘制,避免留白偏位
    var logoAdvance: CGFloat = 0
    if let logo = NSImage(contentsOfFile: logoPath),
       let tiff = logo.tiffRepresentation,
       let lrep = NSBitmapImageRep(data: tiff) {
        let side: CGFloat = 44
        // 内容包围盒 → 等比缩放到 side
        let lw = lrep.pixelsWide, lh = lrep.pixelsHigh
        var minX = lw, minY = lh, maxX = -1, maxY = -1
        for px in stride(from: 0, to: lw, by: 2) {
            for py in stride(from: 0, to: lh, by: 2) {
                guard let c = lrep.colorAt(x: px, y: py), c.alphaComponent > 0.15 else { continue }
                minX = min(minX, px); maxX = max(maxX, px)
                minY = min(minY, py); maxY = max(maxY, py)
            }
        }
        let cw = max(1, maxX - minX + 1), ch = max(1, maxY - minY + 1)
        let s = min(side / CGFloat(cw), side / CGFloat(ch))
        let dw = CGFloat(cw) * s, dh = CGFloat(ch) * s
        let tinted = logo.copy() as! NSImage
        tinted.lockFocus()
        NSColor.white.set()
        NSRect(origin: .zero, size: logo.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        let ly = H - (bannerH - dh) / 2 - dh - 4
        tinted.draw(in: NSRect(x: 226, y: ly, width: dw, height: dh),
                    from: NSRect(x: CGFloat(minX), y: CGFloat(lh - maxY - 1),
                                 width: CGFloat(cw), height: CGFloat(ch)),
                    operation: .sourceOver, fraction: 1.0)
        logoAdvance = dw + 16
    }

    // 横幅文字
    let textX = 226 + (logoAdvance > 0 ? logoAdvance : 60)
    let textW = W - textX - 90
    // 品牌:主名 SlowQ + 中文名 慢Q
    let title = NSMutableAttributedString(string: "SlowQ", attributes: [
        .font: NSFont.systemFont(ofSize: 27, weight: .bold),
        .foregroundColor: NSColor.white,
    ])
    title.append(NSAttributedString(string: "  慢Q", attributes: [
        .font: NSFont.systemFont(ofSize: 17, weight: .semibold),
        .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.72),
    ]))
    let titleSize = title.size()
    title.draw(at: NSPoint(x: textX, y: H - 18 - titleSize.height))
    drawText("防误触退出助手 · 退一步，再确认。", topY: 55,
             font: .systemFont(ofSize: 14, weight: .medium),
             color: .white, align: .left, x: textX, width: textW)
    drawText("Slow down quitting.", topY: 77,
             font: .systemFont(ofSize: 12, weight: .regular),
             color: NSColor(calibratedWhite: 1, alpha: 0.78), align: .left, x: textX, width: textW)

    // ── 拖拽箭头 ──
    // 图标中心(设计稿 topY=250):app 在 x=175、Applications 在 x=505,见 release.sh
    let arrowTopY: CGFloat = 246
    let ay = H - arrowTopY
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 272, y: ay))
    arrow.curve(to: NSPoint(x: 402, y: ay),
                controlPoint1: NSPoint(x: 320, y: ay + 34),
                controlPoint2: NSPoint(x: 356, y: ay + 34))
    arrow.lineWidth = 3
    arrow.lineCapStyle = .round
    arrowColor.setStroke()
    arrow.stroke()

    let head = NSBezierPath()
    head.move(to: NSPoint(x: 406, y: ay))
    head.line(to: NSPoint(x: 386, y: ay + 13))
    head.line(to: NSPoint(x: 386, y: ay - 13))
    head.close()
    arrowColor.setFill()
    head.fill()

    // ── 底部说明(中英双语) ──
    drawText("把左侧的 SlowQ 拖到右侧的「应用程序」文件夹,即可完成安装",
             topY: 368, font: .systemFont(ofSize: 16, weight: .semibold), color: textPrimary)
    drawText("Drag SlowQ into the Applications folder to install",
             topY: 396, font: .systemFont(ofSize: 13, weight: .regular), color: textSecondary)

    NSColor(calibratedWhite: 0.84, alpha: 1).setFill()
    NSRect(x: 96, y: H - 428, width: W - 192, height: 1).fill()

    drawText("首次打开若提示「无法打开」,请在「终端」执行:",
             topY: 440, font: .systemFont(ofSize: 12.5, weight: .medium), color: textSecondary)
    drawText("If macOS blocks the first launch, run this in Terminal:",
             topY: 461, font: .systemFont(ofSize: 12, weight: .regular), color: textSecondary)

    // 命令行代码框
    let cmd = "xattr -dr com.apple.quarantine /Applications/SlowQ.app"
    let cmdString = NSAttributedString(string: cmd, attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .medium),
        .foregroundColor: NSColor(calibratedRed: 0.10, green: 0.29, blue: 0.52, alpha: 1),
    ])
    let cmdSize = cmdString.size()
    let boxH: CGFloat = 28
    let boxRect = rect(topY: 482, height: boxH,
                       x: (W - (cmdSize.width + 32)) / 2, width: cmdSize.width + 32)
    let box = NSBezierPath(roundedRect: boxRect, xRadius: 5, yRadius: 5)
    NSColor(calibratedWhite: 1.0, alpha: 0.92).setFill()
    box.fill()
    NSColor(calibratedWhite: 0.82, alpha: 1).setStroke()
    box.lineWidth = 1
    box.stroke()
    cmdString.draw(at: NSPoint(x: boxRect.minX + 14,
                              y: boxRect.minY + (boxH - cmdSize.height) / 2))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
guard let rep = render(scale: outScale),
      let png = rep.representation(using: .png, properties: [:]) else {
    print("❌ 渲染失败")
    exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: "\(outDir)/background.png"))
} catch {
    print("❌ 写入失败: \(error.localizedDescription)")
    exit(1)
}
print("   ✓ background.png \(Int(W * outScale))x\(Int(H * outScale))px (设计 \(Int(W))x\(Int(H))pt ×\(Int(outScale)))")
