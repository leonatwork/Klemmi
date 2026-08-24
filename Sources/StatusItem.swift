import AppKit

/// Symbol in der Menüleiste samt Popover mit dem Verlauf.
final class StatusItemController: NSObject, NSPopoverDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let listController = HistoryListController()

    override init() {
        super.init()

        statusItem.autosaveName = "KlemmiStatusItem"
        statusItem.behavior = []
        statusItem.isVisible = true
        statusItem.button?.image = Self.menuBarIcon()
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "Klemmi – Zwischenablage-Verlauf"
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

        let dock = NSMenuItem(title: "Im Dock anzeigen", action: #selector(toggleDock), keyEquivalent: "")
        dock.state = Settings.showInDock ? .on : .off
        menu.addItem(dock)

        let concealed = NSMenuItem(title: "Passwörter & sensible Inhalte ignorieren",
                                    action: #selector(toggleConcealed), keyEquivalent: "")
        concealed.state = Settings.ignoreConcealed ? .on : .off
        menu.addItem(concealed)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Verlauf leeren", action: #selector(clearHistory), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Klemmi beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self } }

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleDock() {
        Settings.showInDock.toggle()
        NSApp.setActivationPolicy(Settings.showInDock ? .regular : .accessory)
        if Settings.showInDock { NSApp.activate(ignoringOtherApps: true) }
    }

    @objc private func toggleConcealed() { Settings.ignoreConcealed.toggle() }

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
