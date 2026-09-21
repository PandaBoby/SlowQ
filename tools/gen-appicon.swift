// gen-appicon.swift — 从源图生成正方形 App 图标底图
//
// 用法: swift tools/gen-appicon.swift <源图.png> <输出.png> [内容占比]
//
// 为什么需要它:
//   macOS 的 App 图标画布必须是正方形,但源图往往是横版(本项目为 384x256)。
//   若直接用 `sips -z N N` 强行缩放,会把横版图压成正方形 —— 图形被纵向拉伸变形。
//   本工具按原始宽高比等比放入正方形画布并居中留白,再交给 sips 缩放到各尺寸。
//
// 内容占比 = 图形最长边占画布的比例(默认 0.86,接近 macOS 图标的安全区)。

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("用法: swift tools/gen-appicon.swift <源图.png> <输出.png> [内容占比 0..1]")
    exit(1)
}
let srcPath = args[1]
let outPath = args[2]
let fraction: CGFloat = args.count >= 4 ? (Double(args[3]).map { CGFloat($0) } ?? 0.86) : 0.86
let CANVAS = 1024

guard let srcImage = NSImage(contentsOfFile: srcPath),
      let srcTIFF = srcImage.tiffRepresentation,
      let srcRep = NSBitmapImageRep(data: srcTIFF),
      let srcCG = srcRep.cgImage else {
    print("❌ 无法读取源图: \(srcPath)")
    exit(1)
}

// ── 1. 裁到内容(去掉源图可能带的透明边距) ──
let srcW = srcCG.width, srcH = srcCG.height
var minX = srcW, minY = srcH, maxX = -1, maxY = -1
for x in 0..<srcW {
    for y in 0..<srcH {
        guard let c = srcRep.colorAt(x: x, y: y), c.alphaComponent > 0.15 else { continue }
        if x < minX { minX = x }
        if x > maxX { maxX = x }
        if y < minY { minY = y }
        if y > maxY { maxY = y }
    }
}
guard maxX >= minX, maxY >= minY else {
    print("❌ 源图完全透明")
    exit(1)
}
let contentW = maxX - minX + 1
let contentH = maxY - minY + 1
guard let cropped = srcCG.cropping(to: CGRect(x: minX, y: minY, width: contentW, height: contentH)) else {
    print("❌ 裁剪失败")
    exit(1)
}

// ── 2. 等比放入正方形画布并居中 ──
let safe = CGFloat(CANVAS) * fraction
let scale = min(safe / CGFloat(contentW), safe / CGFloat(contentH))
let drawW = (CGFloat(contentW) * scale).rounded()
let drawH = (CGFloat(contentH) * scale).rounded()
let originX = ((CGFloat(CANVAS) - drawW) / 2).rounded()
let originY = ((CGFloat(CANVAS) - drawH) / 2).rounded()

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil, width: CANVAS, height: CANVAS,
    bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    print("❌ 创建画布失败")
    exit(1)
}
ctx.interpolationQuality = .high
ctx.clear(CGRect(x: 0, y: 0, width: CANVAS, height: CANVAS))
ctx.draw(cropped, in: CGRect(x: originX, y: originY, width: drawW, height: drawH))

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
guard CGImageDestinationFinalize(dest) else {
    print("❌ 编码失败")
    exit(1)
}
do {
    try (data as Data).write(to: URL(fileURLWithPath: outPath), options: .atomic)
} catch {
    print("❌ 写入失败: \(outPath) — \(error.localizedDescription)")
    exit(1)
}

print("   ✓ 底图 \(CANVAS)x\(CANVAS),内容 \(contentW)x\(contentH) → \(Int(drawW))x\(Int(drawH)) (等比,宽高比 \(String(format: "%.2f", Double(contentW) / Double(contentH))))")
