import Cocoa
import ObjectiveC

// MARK: - Entry

// NSApplication.delegate 是 weak 引用,必须强引用保活。
// 用 objc 关联对象把 delegate 挂在 app 上,防止编译优化释放全局变量。
var kSlowQDelegateKey: Void = ()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
objc_setAssociatedObject(app, &kSlowQDelegateKey, delegate, .OBJC_ASSOCIATION_RETAIN)
app.setActivationPolicy(.accessory) // 菜单栏应用,不占 Dock
app.run()
