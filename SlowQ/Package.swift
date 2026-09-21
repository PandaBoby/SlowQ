// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SlowQ",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SlowQ",
            path: "src",
            resources: [
                // 菜单栏图标:1x 像素尺寸 == 逻辑点数,2x 供 Retina
                // 由 tools/gen-statusbar.swift 从源图标自动生成
                .copy("Resources/statusbar.png"),
                .copy("Resources/statusbar@2x.png"),
            ]
        )
    ]
)
