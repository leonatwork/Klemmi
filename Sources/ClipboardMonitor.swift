import AppKit

/// Pollt die Systemzwischenablage (es gibt keine Änderungs-Benachrichtigung von macOS)
/// und legt neue Inhalte samt Quell-App im HistoryStore ab.
final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    private static let pngType = NSPasteboard.PasteboardType(rawValue: "public.png")
    private static let concealedType = NSPasteboard.PasteboardType(rawValue: "org.nspasteboard.ConcealedType")
    private static let transientType = NSPasteboard.PasteboardType(rawValue: "org.nspasteboard.TransientType")

    private var timer: Timer?
    private let pasteboard: NSPasteboard
    private let store: HistoryStore
    private var lastChangeCount: Int

    /// Wird kurz gesetzt, wenn Klemmi selbst etwas in die Zwischenablage schreibt,
    /// damit dieser Schreibvorgang nicht als neuer Verlaufseintrag erfasst wird.
    var ignoredChangeCount: Int?

    init(pasteboard: NSPasteboard = .general, store: HistoryStore = .shared) {
        self.pasteboard = pasteboard
        self.store = store
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        lastChangeCount = pasteboard.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stopAndCapturePendingChange() {
        timer?.invalidate()
        timer = nil
        poll()
    }

    func poll() {
        let pb = pasteboard
        let count = pb.changeCount
        guard count != lastChangeCount else { return }
        let capture = HistorySafety.shouldCapture(changeCount: count, lastChangeCount: lastChangeCount,
                                                  ignoredChangeCount: ignoredChangeCount)
        lastChangeCount = count
        ignoredChangeCount = nil
        guard capture else { return }

        let types = pb.types ?? []
        if Settings.ignoreConcealed,
           types.contains(Self.concealedType) || types.contains(Self.transientType) {
            return
        }

        let app = NSWorkspace.shared.frontmostApplication
        let sourceName = app?.localizedName
        let sourceBundle = app?.bundleIdentifier

        if types.contains(.tiff) || types.contains(Self.pngType),
            let data = pb.data(forType: Self.pngType) ?? pb.data(forType: .tiff) {
            store.addImage(data, sourceAppName: sourceName, sourceBundleID: sourceBundle)
        } else if let text = pb.string(forType: .string), !text.isEmpty {
            store.addText(text, sourceAppName: sourceName, sourceBundleID: sourceBundle)
        }
    }
}
