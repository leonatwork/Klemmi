import AppKit

/// Rahmenloses Panel, das Tastatureingaben annimmt, ohne Klemmi zu aktivieren.
/// ↩ und Esc, die nicht schon das Suchfeld verarbeitet hat (z. B. wenn die Tabelle
/// den Fokus hat), landen hier.
private final class OverlayPanel: NSPanel {
    var onReturn: (() -> Void)?
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onReturn?()   // ↩ und Enter auf dem Ziffernblock
        case 53: onEscape?()       // Esc
        default: super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

/// Schwebendes Overlay mit dem Verlauf, geöffnet per ⌘⇧C (das Win+V-Pendant).
/// Die zuvor aktive App behält den Fokus: Eintrag wählen, Overlay schließt sich,
/// ⌘V fügt direkt dort ein, wo man gerade war.
final class OverlayController: NSObject, NSWindowDelegate {

    private static let size = NSSize(width: 420, height: 480)

    private let panel: OverlayPanel
    private let listController = HistoryListController()
    private var clickMonitor: Any?

    var onOpenFullView: (() -> Void)?

    override init() {
        panel = OverlayPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                             styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                             backing: .buffered, defer: false)
        super.init()

        panel.delegate = self
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.size))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true

        let title = NSTextField(labelWithString: L10n.tr("overlay.title"))
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = .secondaryLabelColor
        title.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(labelWithString: L10n.tr("overlay.hint"))
        hint.font = .systemFont(ofSize: 10.5)
        hint.textColor = .tertiaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false

        listController.keyboardNavigation = true
        let list = listController.view
        list.translatesAutoresizingMaskIntoConstraints = false

        [title, hint, list].forEach { effect.addSubview($0) }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: effect.topAnchor, constant: 10),
            title.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 14),
            hint.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            hint.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -14),

            list.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            list.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            list.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        panel.contentView = effect

        listController.onSelect = { [weak self] item in
            Clipboard.copyToPasteboard(item)
            self?.close()
        }
        listController.onCancel = { [weak self] in self?.close() }
        listController.onOpenFullView = { [weak self] in
            self?.close()
            self?.onOpenFullView?()
        }
        panel.onReturn = { [weak self] in self?.listController.activateSelection() }
        panel.onEscape = { [weak self] in self?.close() }
    }

    // MARK: Öffnen / Schließen

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        if panel.isVisible { close() } else { show() }
    }

    func show() {
        listController.resetSearch()
        position()
        panel.makeKeyAndOrderFront(nil)
        listController.focusSearch()
        installClickMonitor()
    }

    func close() {
        removeClickMonitor()
        panel.orderOut(nil)
    }

    /// Positioniert das Overlay am Mauszeiger (linke obere Ecke auf Cursorhöhe).
    ///
    /// Verhalten wie Kontextmenüs: Wenn rechts oder unten kein Platz ist, wird die
    /// jeweilige Achse am Cursor gespiegelt. Passt es danach immer noch nicht, wird
    /// in `screen.visibleFrame` verschoben. Falls kein Bildschirm zur Maus passt,
    /// wird auf die Mitte von `NSScreen.main.visibleFrame` zurückgefallen.
    private func position() {
        let mouse = NSEvent.mouseLocation
        let size = panel.frame.size

        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            panel.setFrameOrigin(OverlayPositioning.overlayOrigin(mouse: mouse, visibleFrame: screen.visibleFrame, size: size))
            return
        }

        guard let visibleFrame = NSScreen.main?.visibleFrame else { return }
        panel.setFrameOrigin(OverlayPositioning.centeredOrigin(visibleFrame: visibleFrame, size: size))
    }

    // MARK: Klicks außerhalb

    /// Mausklicks in anderen Apps schließen das Overlay. Globale Maus-Monitore
    /// brauchen im Gegensatz zu Tastatur-Monitoren keine Berechtigung.
    private func installClickMonitor() {
        removeClickMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
    }

    private func removeClickMonitor() {
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
    }

    func windowDidResignKey(_ notification: Notification) { close() }
}
