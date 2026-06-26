import AppKit
import RoutingCore

// Hidden CLI: print detected audio devices and exit (manual verification).
if CommandLine.arguments.contains("--list") {
    let manager = AudioDeviceManager()
    let outID = manager.defaultOutputDevice()
    let inID = manager.defaultInputDevice()
    for d in manager.allDevices() {
        var flags: [String] = []
        flags.append(d.transport == .bluetooth ? "BT " : "   ")
        flags.append(d.hasOutput ? "out" : "   ")
        flags.append(d.hasInput ? "in" : "  ")
        if d.id == outID { flags.append("[default-out]") }
        if d.id == inID { flags.append("[default-in]") }
        print("\(d.id)\t\(flags.joined(separator: " "))\t\(d.name)")
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
app.run()
