import Cocoa
import ObjectiveC

// MARK: - Entry

// NSApplication.delegate 是 weak 引用。app.run() 不返回,
// 全局 let 本身保活;objc 关联对象作为显式强引用双保险。
var kSlowQDelegateKey: Void = ()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
objc_setAssociatedObject(app, &kSlowQDelegateKey, delegate, .OBJC_ASSOCIATION_RETAIN)
app.setActivationPolicy(.accessory) // 菜单栏应用,不占 Dock
app.run()
