// gen-volumeicon.swift — 生成 DMG 卷图标(挂载后显示在桌面/Finder 的磁盘图标)
//
// 用法: swift tools/gen-volumeicon.swift <输出.png> [尺寸] [logo图路径]
//
// 造型参考 macOS 外置磁盘:圆角机身 + 底部接缝 + 电源指示灯 + 居中的品牌 logo。
// 配色与安装界面横幅一致(深板岩渐变 + 白色 logo),让整条安装体验视觉统一。
//
// 输出为正方形 PNG(默认 1024),再由 make-dmg.sh 经 sips + iconutil 转成 .VolumeIcon.icns。

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("用法: swift tools/gen-volumeicon.swift <输出.png> [尺寸] [logo图路径]")
    exit(1)
}
let outPath = args[1]
let SIZE = args.count >= 3 ? (Double(args[2]).map { Int($0) } ?? 1024) : 1024
let logoPath = args.count >= 4
    ? args[3]
    : (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent("SlowQ/SlowQ.png")

let S = CGFloat(SIZE)

// ── 配色(与 tools/gen-dmgbackground.swift 的横幅一致)──
let bodyTop = CGColor(red: 0.30, green: 0.34, blue: 0.41, alpha: 1)
let bodyBottom = CGColor(red: 0.13, green: 0.15, blue: 0.19, alpha: 1)
let seamColor = CGColor(red: 0.09, green: 0.10, blue: 0.13, alpha: 1)
let edgeColor = CGColor(red: 0.55, green: 0.60, blue: 0.68, alpha: 0.55)
let ledColor = CGColor(red: 0.24, green: 0.82, blue: 0.48, alpha: 1)

guard let ctx = CGContext(
    data: nil, width: SIZE, height: SIZE,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    print("❌ 创建画布失败")
    exit(1)
}
ctx.interpolationQuality = .high
ctx.clear(CGRect(x: 0, y: 0, width: S, height: S))
ctx.setAllowsAntialiasing(true)

// 设计坐标(以 1024 为基准,按尺寸等比缩放)
let k = S / 1024
func r(_ v: CGFloat) -> CGFloat { v * k }

let bodyRect = CGRect(x: r(92), y: r(180), width: r(840), height: r(664))
let corner = r(104)
let seamY = bodyRect.minY + bodyRect.height * r(0.24)   // 接缝距底部 24%

// ── 机身阴影 ──
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: r(-14)), blur: r(34),
              color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.42))
let bodyPath = CGPath(roundedRect: bodyRect, cornerWidth: corner, cornerHeight: corner, transform: nil)
ctx.addPath(bodyPath)
ctx.setFillColor(bodyBottom)
ctx.fillPath()
ctx.restoreGState()

// ── 机身渐变 ──
ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [bodyTop, bodyBottom] as CFArray,
                          locations: [0, 1])!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: 0, y: bodyRect.maxY),
                       end: CGPoint(x: 0, y: bodyRect.minY),
                       options: [])
// 顶部高光,模拟金属反光
let gloss = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                       colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 0.20),
                                CGColor(red: 1, green: 1, blue: 1, alpha: 0.0)] as CFArray,
                       locations: [0, 1])!
ctx.drawLinearGradient(gloss,
                       start: CGPoint(x: 0, y: bodyRect.maxY),
                       end: CGPoint(x: 0, y: bodyRect.maxY - bodyRect.height * 0.42),
                       options: [])
// 底部接缝(略深的一条带)
ctx.setFillColor(seamColor)
ctx.fill(CGRect(x: bodyRect.minX, y: bodyRect.minY, width: bodyRect.width,
                height: bodyRect.minY + bodyRect.height * 0.24 - bodyRect.minY))
ctx.restoreGState()

// 接缝上沿的细高光
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.14))
ctx.fill(CGRect(x: bodyRect.minX + r(26), y: seamY, width: bodyRect.width - r(52), height: r(3)))

// ── 机身描边 ──
ctx.addPath(bodyPath)
ctx.setStrokeColor(edgeColor)
ctx.setLineWidth(r(3))
ctx.strokePath()

// ── 电源指示灯(带光晕)──
let ledCenter = CGPoint(x: bodyRect.maxX - r(74), y: bodyRect.minY + bodyRect.height * 0.12)
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: r(20), color: ledColor)
ctx.setFillColor(ledColor)
ctx.fillEllipse(in: CGRect(x: ledCenter.x - r(15), y: ledCenter.y - r(15),
                           width: r(30), height: r(30)))
ctx.restoreGState()
// 灯芯高光
ctx.setFillColor(CGColor(red: 0.78, green: 1, blue: 0.86, alpha: 0.9))
ctx.fillEllipse(in: CGRect(x: ledCenter.x - r(5), y: ledCenter.y - r(5),
                           width: r(10), height: r(10)))

// ── 品牌 logo(白色版,居中于机身上半部)──
if let logo = NSImage(contentsOfFile: logoPath),
   let tiff = logo.tiffRepresentation,
   let lrep = NSBitmapImageRep(data: tiff),
   let lcg = lrep.cgImage {
    // 内容包围盒 → 等比缩放
    let lw = lcg.width, lh = lcg.height
    var minX = lw, minY = lh, maxX = -1, maxY = -1
    for px in stride(from: 0, to: lw, by: 2) {
        for py in stride(from: 0, to: lh, by: 2) {
            guard let c = lrep.colorAt(x: px, y: py), c.alphaComponent > 0.15 else { continue }
            minX = min(minX, px); maxX = max(maxX, px)
            minY = min(minY, py); maxY = max(maxY, py)
        }
    }
    let cw = max(1, maxX - minX + 1), ch = max(1, maxY - minY + 1)
    guard let cropped = lcg.cropping(to: CGRect(x: minX, y: minY, width: cw, height: ch)) else {
        print("❌ logo 裁剪失败"); exit(1)
    }

    // 把 logo 染成白色(保留 alpha)
    let tintW = cw, tintH = ch
    guard let tctx = CGContext(data: nil, width: tintW, height: tintH,
                               bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        print("❌ 创建 logo 画布失败"); exit(1)
    }
    tctx.draw(cropped, in: CGRect(x: 0, y: 0, width: tintW, height: tintH))
    tctx.setBlendMode(.sourceIn)
    tctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    tctx.fill(CGRect(x: 0, y: 0, width: tintW, height: tintH))
    guard let whiteLogo = tctx.makeImage() else { print("❌ logo 着色失败"); exit(1) }

    // 目标尺寸:机身宽度的 42%,等比
    let targetW = bodyRect.width * 0.42
    let targetH = targetW * CGFloat(ch) / CGFloat(cw)
    // 居中于机身上半部(接缝以上区域的中心)
    let upperCenterY = (seamY + bodyRect.maxY) / 2
    let logoRect = CGRect(x: bodyRect.midX - targetW / 2, y: upperCenterY - targetH / 2,
                          width: targetW, height: targetH)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: r(-4)), blur: r(18),
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
    ctx.draw(whiteLogo, in: logoRect)
    ctx.restoreGState()
} else {
    print("⚠️  未找到 logo: \(logoPath),仅生成机身")
}

guard let outCG = ctx.makeImage() else {
    print("❌ 渲染失败")
    exit(1)
}
let data = NSMutableData()
guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
    print("❌ 创建输出失败")
    exit(1)
}
CGImageDestinationAddImage(dest, outCG, nil)
guard CGImageDestinationFinalize(dest) else { print("❌ 编码失败"); exit(1) }
do {
    try (data as Data).write(to: URL(fileURLWithPath: outPath), options: .atomic)
} catch {
    print("❌ 写入失败: \(error.localizedDescription)")
    exit(1)
}
print("   ✓ 卷图标底图 \(SIZE)x\(SIZE)px")
