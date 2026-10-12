import AppKit

/// Symbol in der Menüleiste samt Popover mit dem Verlauf.
final class StatusItemController: NSObject, NSPopoverDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let listController = HistoryListController()
    private weak var mainWindow: MainWindowController?

    init(mainWindow: MainWindowController) {
        self.mainWindow = mainWindow
        super.init()

        statusItem.autosaveName = "KlemmiStatusItem"
        statusItem.behavior = []
        statusItem.isVisible = true
        statusItem.button?.image = Self.menuBarIcon()
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = L10n.tr("statusItem.tooltip")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(click(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = listController

        listController.onSelect = { [weak self] item in
            Clipboard.copyToPasteboard(item)
            self?.popover.performClose(nil)
        }
        listController.onOpenFullView = { [weak self] in
            self?.popover.performClose(nil)
            self?.openMainWindow()
        }
    }

    // MARK: Interaktion

    @objc private func click(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let secondary = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if secondary { showMenu() } else { togglePopover() }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            listController.reload()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        menu.addItem(withTitle: L10n.tr("menu.openOverview"), action: #selector(openMainWindow), keyEquivalent: "")
        menu.addItem(.separator())

        let dock = NSMenuItem(title: L10n.tr("menu.showInDock"), action: #selector(toggleDock), keyEquivalent: "")
        dock.state = Settings.showInDock ? .on : .off
        menu.addItem(dock)

        let concealed = NSMenuItem(title: L10n.tr("menu.ignoreConcealed"),
                                    action: #selector(toggleConcealed), keyEquivalent: "")
        concealed.state = Settings.ignoreConcealed ? .on : .off
        menu.addItem(concealed)

        let hotKey = NSMenuItem(title: L10n.tr("menu.overlayHotKey", OverlayHotKey.displayString),
                                action: #selector(toggleHotKey), keyEquivalent: "")
        hotKey.state = Settings.overlayHotKeyEnabled ? .on : .off
        menu.addItem(hotKey)

        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.tr("menu.clearHistory"), action: #selector(clearHistory), keyEquivalent: "")
        menu.addItem(.separator())
        let more = NSMenuItem(title: L10n.tr("menu.moreApps"), action: nil, keyEquivalent: "")
        more.submenu = moreAppsMenu()
        menu.addItem(more)
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.tr("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self } }

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: Weitere Apps

    /// Die anderen Tools aus dem Paket „I love macOS, but I miss some Windows features“.
    private static let siblingApps: [(name: String, descriptionKey: String, url: String)] = [
        ("Tappi", "moreApps.tappi", "https://github.com/leonatwork/Tappi"),
        ("Snapline", "moreApps.snapline", "https://github.com/leonatwork/snapline"),
        ("Snapboard", "moreApps.snapboard", "https://github.com/leonatwork/snapboard"),
    ]
    private static let packageURL =
        "https://github.com/search?q=topic%3Ai-love-macos-but-i-miss-windows-features+user%3Aleonatwork&type=repositories"

    private func moreAppsMenu() -> NSMenu {
        let sub = NSMenu()
        for app in Self.siblingApps {
            let item = NSMenuItem(title: "\(app.name) – \(L10n.tr(app.descriptionKey))",
                                  action: #selector(openLink(_:)), keyEquivalent: "")
            item.representedObject = URL(string: app.url)
            item.target = self
            sub.addItem(item)
        }
        sub.addItem(.separator())
        let package = NSMenuItem(title: L10n.tr("menu.moreApps.package"),
                                 action: #selector(openLink(_:)), keyEquivalent: "")
        package.representedObject = URL(string: Self.packageURL)
        package.target = self
        sub.addItem(package)
        return sub
    }

    @objc private func openLink(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.showWindow(nil)
        mainWindow?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleDock() {
        Settings.showInDock.toggle()
        NSApp.setActivationPolicy(Settings.showInDock ? .regular : .accessory)
        if Settings.showInDock { NSApp.activate(ignoringOtherApps: true) }
    }

    @objc private func toggleConcealed() { Settings.ignoreConcealed.toggle() }

    @objc private func toggleHotKey() {
        Settings.overlayHotKeyEnabled.toggle()
        OverlayHotKey.shared.apply()
    }

    @objc private func clearHistory() { HistoryStore.shared.clear() }

    // MARK: Symbol

    private static func menuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        let s: CGFloat = 18

        let board = NSBezierPath(roundedRect: NSRect(x: s*0.2, y: s*0.06, width: s*0.6, height: s*0.84), xRadius: 2, yRadius: 2)
        board.lineWidth = 1.4
        NSColor.black.setStroke()
        board.stroke()

        NSBezierPath(roundedRect: NSRect(x: s*0.38, y: s*0.80, width: s*0.24, height: s*0.14), xRadius: 1.5, yRadius: 1.5)
            .fill()

        for y: CGFloat in [0.60, 0.45, 0.30] {
            let line = NSBezierPath()
            line.lineWidth = 1.2
            line.move(to: NSPoint(x: s*0.32, y: s*y))
            line.line(to: NSPoint(x: s*0.68, y: s*y))
            line.stroke()
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
