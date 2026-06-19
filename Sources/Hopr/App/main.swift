import Cocoa

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // Run in background, no dock icon initially

let delegate = AppDelegate()
app.delegate = delegate
app.run()
