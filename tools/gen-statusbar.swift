// gen-statusbar.swift — 从源图标生成菜单栏图标
//
// 用法: swift tools/gen-statusbar.swift <源图.png> <输出目录> [内容高度pt]
//
// 处理流程:
//   1. 扫描 alpha 通道求"内容包围盒",裁掉透明边距
//      (这是菜单栏图标显得比别的图标小的根因:整张画布缩放时,透明边距也占尺寸)
//   2. 按内容高度 = 目标高度pt 等比缩放到 1x / 2x
//   3. 输出 statusbar.png(1x) 与 statusbar@2x.png(2x)
//      1x 文件的像素尺寸 == 逻辑点数,App 侧据此设置 image.size,避免拉伸变形
//
// 用 CoreGraphics 而非 AppKit 绘制:NSImage(cgImage:size:) 的逻辑尺寸与像素尺寸
// 不一致时 AppKit 绘制会静默产出错误结果。

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("用法: swift tools/gen-statusbar.swift <源图.png> <输出目录> [内容高度pt]")
    exit(1)
}
let srcPath = args[1]
let outDir = args[2]
// 菜单栏图标视觉高度(点)。macOS 状态栏图标常见 14–18pt,默认 15pt
let TARGET_HEIGHT_PT: CGFloat = args.count >= 4 ? (Double(args[3]).map { CGFloat($0) } ?? 15) : 15

guard let srcImage = NSImage(contentsOfFile: srcPath),
      let srcTIFF = srcImage.tiffRepresentation,
      let srcRep = NSBitmapImageRep(data: srcTIFF),
      let srcCG = srcRep.cgImage else {
    print("❌ 无法读取源图: \(srcPath)")
    exit(1)
}

let srcW = srcCG.width
let srcH = srcCG.height

// ── 1. 求内容包围盒(alpha > 阈值,colorAt 以左上为原点) ──
// 阈值 0.15:忽略抗锯齿产生的近乎透明的边缘像素,取到真实可见轮廓
let ALPHA_THRESHOLD: CGFloat = 0.15
var minX = srcW, minY = srcH, maxX = -1, maxY = -1
for x in 0..<srcW {
    for y in 0..<srcH {
        guard let c = srcRep.colorAt(x: x, y: y), c.alphaComponent > ALPHA_THRESHOLD else { continue }
        if x < minX { minX = x }
        if x > maxX { maxX = x }
        if y < minY { minY = y }
        if y > maxY { maxY = y }
    }
}
guard maxX >= minX, maxY >= minY else {
    print("❌ 源图完全透明,无内容")
    exit(1)
}
let contentW = maxX - minX + 1
let contentH = maxY - minY + 1
print("   源图 \(srcW)x\(srcH),内容包围盒 \(contentW)x\(contentH) (裁掉上 \(minY)px / 下 \(srcH-1-maxY)px)")

// 裁到内容。CGImage.cropping 同以左上为原点,与包围盒坐标一致
guard let cropped = srcCG.cropping(to: CGRect(x: minX, y: minY, width: contentW, height: contentH)) else {
    print("❌ 裁剪失败")
    exit(1)
}

// ── 2. 等比缩放 ──
let aspect = CGFloat(contentW) / CGFloat(contentH)
let h2x = Int((TARGET_HEIGHT_PT * 2).rounded())
let w2x = max(1, Int((CGFloat(h2x) * aspect).rounded()))
let h1x = Int(TARGET_HEIGHT_PT.rounded())
let w1x = max(1, Int((CGFloat(h1x) * aspect).rounded()))

/// 用 CGContext 缩放绘制,输出 PNG 数据
func scaleToPNG(_ image: CGImage, width: Int, height: Int) -> Data? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    // 缩小图用高质量插值,避免像素走样(源图为像素画,直接丢行列会产生断线)
    ctx.interpolationQuality = .high
    ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let outCG = ctx.makeImage() else { return nil }

    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(
        data, UTType.png.identifier as CFString, 1, nil
    ) else { return nil }
    CGImageDestinationAddImage(dest, outCG, nil)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return data as Data
}

// ── 3. 输出 ──
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

guard let png2x = scaleToPNG(cropped, width: w2x, height: h2x) else {
    print("❌ 2x 渲染失败")
    exit(1)
}
let dest2x = "\(outDir)/statusbar@2x.png"
try? png2x.write(to: URL(fileURLWithPath: dest2x))
print("   ✓ statusbar@2x.png \(w2x)x\(h2x)px")

// 1x 由 2x 结果再缩,保证两个尺寸视觉一致
guard let img2x = NSImage(data: png2x),
      let rep2x = NSBitmapImageRep(data: img2x.tiffRepresentation!),
      let cg2x = rep2x.cgImage,
      let png1x = scaleToPNG(cg2x, width: w1x, height: h1x) else {
    print("❌ 1x 渲染失败")
    exit(1)
}
let dest1x = "\(outDir)/statusbar.png"
try? png1x.write(to: URL(fileURLWithPath: dest1x))
print("   ✓ statusbar.png \(w1x)x\(h1x)px (= \(Int(TARGET_HEIGHT_PT))pt 高)")
