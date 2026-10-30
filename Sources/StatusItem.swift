import AppKit
import ServiceManagement

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
        statusItem.button?.imagePosition = .imageOnly
        updateRecordingStatus()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(click(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = listController

        // Im Popover ist Klemmi selbst aktiv; direktes Einfügen gibt es nur im Overlay.
        listController.onSelect = { [weak self] item, _ in
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

        let loginItem = NSMenuItem(title: "", action: #selector(toggleLoginItem(_:)), keyEquivalent: "")
        updateLoginItem(loginItem)
        menu.addItem(loginItem)

        let concealed = NSMenuItem(title: L10n.tr("menu.ignoreConcealed"),
                                    action: #selector(toggleConcealed), keyEquivalent: "")
        concealed.state = Settings.ignoreConcealed ? .on : .off
        menu.addItem(concealed)

        let pause = NSMenuItem(title: L10n.tr("menu.pauseRecording"),
                               action: #selector(toggleRecordingPause), keyEquivalent: "")
        pause.state = ClipboardMonitor.shared.isRecordingPaused ? .on : .off
        menu.addItem(pause)

        var hotKeyTitle = L10n.tr("menu.overlayHotKey", OverlayHotKey.displayString)
        if OverlayHotKey.shared.isUnavailable {
            hotKeyTitle = L10n.tr("menu.overlayHotKey.registrationFailed", hotKeyTitle)
        }
        let hotKey = NSMenuItem(title: hotKeyTitle,
                                 action: #selector(toggleHotKey), keyEquivalent: "")
        hotKey.state = OverlayHotKey.shared.isActive ? .on : .off
        menu.addItem(hotKey)
        menu.addItem(withTitle: L10n.tr("menu.changeOverlayHotKey"), action: #selector(changeHotKey), keyEquivalent: "")

        let directPaste = NSMenuItem(title: "", action: #selector(toggleDirectPaste(_:)), keyEquivalent: "")
        updateDirectPaste(directPaste)
        menu.addItem(directPaste)

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

    @objc private func toggleRecordingPause() {
        let monitor = ClipboardMonitor.shared
        monitor.setRecordingPaused(!monitor.isRecordingPaused)
        updateRecordingStatus()
    }

    private func updateRecordingStatus() {
        let paused = ClipboardMonitor.shared.isRecordingPaused
        statusItem.button?.image = Self.menuBarIcon(paused: paused)
        let description = paused ? L10n.tr("statusItem.tooltip.paused") : L10n.tr("statusItem.tooltip")
        statusItem.button?.toolTip = description
        statusItem.button?.setAccessibilityLabel(description)
    }

    private func updateLoginItem(_ item: NSMenuItem) {
        let state = LoginItemPolicy.menuState(for: SMAppService.mainApp.status)
        item.state = state.checkmark
        item.title = state.action == .openSettings
            ? L10n.tr("menu.startAtLogin.requiresApproval")
            : L10n.tr("menu.startAtLogin")
    }

    @objc private func toggleLoginItem(_ sender: NSMenuItem) {
        // Auch beim Klick frisch lesen: Die Systemeinstellungen könnten sich geändert haben.
        LoginItem.perform(LoginItemPolicy.menuState(for: SMAppService.mainApp.status).action)
        // Nie optimistisch umschalten, auch nach einem Fehler gilt nur der Systemstatus.
        updateLoginItem(sender)
    }

    @objc private func toggleHotKey() {
        Settings.overlayHotKeyEnabled.toggle()
        if !OverlayHotKey.shared.apply() {
            if OverlayHotKey.shared.isActive { Settings.overlayHotKeyEnabled = true }
            OverlayHotKey.shared.showRegistrationError()
        }
    }

    @objc private func changeHotKey() {
        popover.performClose(nil)
        guard let shortcut = HotKeyRecorder.record() else { return }
        if !OverlayHotKey.shared.change(to: shortcut) {
            OverlayHotKey.shared.showRegistrationError()
        }
    }

    /// Das Recht bei jedem Menüaufbau frisch lesen: Ein Entzug in den Systemeinstellungen
    /// erscheint als gemischter Zustand mit Hinweis (AC-4).
    private func updateDirectPaste(_ item: NSMenuItem) {
        let state = DirectPastePolicy.menuState(enabled: Settings.directPaste, trusted: DirectPaste.isTrusted())
        item.state = state.checkmark
        item.title = state.checkmark == .mixed
            ? L10n.tr("menu.directPaste.requiresApproval")
            : L10n.tr("menu.directPaste")
    }

    @objc private func toggleDirectPaste(_ sender: NSMenuItem) {
        switch DirectPastePolicy.menuState(enabled: Settings.directPaste, trusted: DirectPaste.isTrusted()).action {
        case .disable:
            Settings.directPaste = false
        case .request:
            // Erklärdialog vor der Systemabfrage; Abbruch lässt die Einstellung aus (AC-2).
            Settings.directPaste = DirectPaste.enable()
        }
    }

    @objc private func clearHistory() { HistoryStore.shared.clear() }

    // MARK: Symbol

    private static func menuBarIcon(paused: Bool) -> NSImage {
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

        if paused {
            NSColor.black.setFill()
            for x: CGFloat in [0.35, 0.55] {
                NSBezierPath(rect: NSRect(x: s*x, y: s*0.28, width: s*0.10, height: s*0.35)).fill()
            }
        } else {
            for y: CGFloat in [0.60, 0.45, 0.30] {
                let line = NSBezierPath()
                line.lineWidth = 1.2
                line.move(to: NSPoint(x: s*0.32, y: s*y))
                line.line(to: NSPoint(x: s*0.68, y: s*y))
                line.stroke()
            }
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
