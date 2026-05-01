// UI を持たない menubar app の最小 bootstrap です。
import AppKit

let application = NSApplication.shared
let delegate = AppDelegate()

application.setActivationPolicy(.accessory)
application.delegate = delegate
application.run()
