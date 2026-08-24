import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(Settings.showInDock ? .regular : .accessory)
        statusItem = StatusItemController()
        ClipboardMonitor.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
