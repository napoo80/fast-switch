import AppKit

//let app = NSApplication.shared
//let delegate = AppDelegate()
//app.delegate = delegate
//app.run()

let app = NSApplication.shared
let appDelegate = AppDelegate()    // 👈 global fuerte
app.delegate = appDelegate
app.run()
