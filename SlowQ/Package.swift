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
                // 状态栏图标(16/32px;运行时按屏幕缩放选择)
                .copy("Resources/statusbar-16.png"),
                .copy("Resources/statusbar-32.png"),
            ]
        )
    ]
)
