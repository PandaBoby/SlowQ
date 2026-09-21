import Cocoa

// MARK: - Entry

// NSApplication.delegate 是 weak 引用,必须有别的东西持有 AppDelegate。
// 这里只保留**一种**保活方式:文件作用域的全局 `let`。
// Swift 全局变量具有静态存储期,初始化后不会被释放,生命周期覆盖整个进程,
// 而 app.run() 本就不返回 —— 这已经足够。
//
// 此前额外用 objc 关联对象做"双保险",但那个关联键是零尺寸的 `Void` 全局:
// Swift 不保证零尺寸值拥有唯一存储地址,它可能与进程中其它零尺寸全局取到
// 同一地址,导致 objc 关联互相覆盖。双重保活还会让 deinit 永不执行。
// 因此移除关联对象,只留全局持有。

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // 菜单栏应用,不占 Dock
app.run()
