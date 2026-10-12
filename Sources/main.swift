import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let mainWindow = MainWindowController()
    private let overlay = OverlayController()
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(Settings.showInDock ? .regular : .accessory)
        statusItem = StatusItemController(mainWindow: mainWindow)
        ClipboardMonitor.shared.start()

        overlay.onOpenFullView = { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.mainWindow.showWindow(nil)
            self?.mainWindow.window?.makeKeyAndOrderFront(nil)
        }
        OverlayHotKey.shared.onPressed = { [weak self] in self?.overlay.toggle() }
        OverlayHotKey.shared.apply()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { mainWindow.showWindow(nil) }
        return true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
