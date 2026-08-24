import AppKit

/// Pollt die Systemzwischenablage (es gibt keine Änderungs-Benachrichtigung von macOS)
/// und legt neue Inhalte samt Quell-App im HistoryStore ab.
final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    private static let pngType = NSPasteboard.PasteboardType(rawValue: "public.png")
    private static let concealedType = NSPasteboard.PasteboardType(rawValue: "org.nspasteboard.ConcealedType")
    private static let transientType = NSPasteboard.PasteboardType(rawValue: "org.nspasteboard.TransientType")

    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount

    /// Wird kurz gesetzt, wenn Klemmi selbst etwas in die Zwischenablage schreibt,
    /// damit dieser Schreibvorgang nicht als neuer Verlaufseintrag erfasst wird.
    var ignoreNextChange = false

    func start() {
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        if ignoreNextChange {
            ignoreNextChange = false
            return
        }

        let types = pb.types ?? []
        if Settings.ignoreConcealed,
           types.contains(Self.concealedType) || types.contains(Self.transientType) {
            return
        }

        let app = NSWorkspace.shared.frontmostApplication
        let sourceName = app?.localizedName
        let sourceBundle = app?.bundleIdentifier

        if types.contains(.tiff) || types.contains(Self.pngType),
           let data = pb.data(forType: Self.pngType) ?? pb.data(forType: .tiff),
           let image = NSImage(data: data) {
            HistoryStore.shared.addImage(image, sourceAppName: sourceName, sourceBundleID: sourceBundle)
        } else if let text = pb.string(forType: .string), !text.isEmpty {
            HistoryStore.shared.addText(text, sourceAppName: sourceName, sourceBundleID: sourceBundle)
        }
    }
}
