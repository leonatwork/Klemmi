import AppKit

/// Pollt die Systemzwischenablage (es gibt keine Änderungs-Benachrichtigung von macOS)
/// und legt neue Inhalte samt Quell-App im HistoryStore ab.
final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    private static let pngType = NSPasteboard.PasteboardType(rawValue: "public.png")

    private var timer: Timer?
    private let pasteboard: NSPasteboard
    private let store: HistoryStore
    private let sourceApplication: () -> (name: String?, bundleID: String?)
    private var lastChangeCount: Int

    /// Session-only: restarting Klemmi always resumes recording.
    private(set) var isRecordingPaused = false

    /// Wird kurz gesetzt, wenn Klemmi selbst etwas in die Zwischenablage schreibt,
    /// damit dieser Schreibvorgang nicht als neuer Verlaufseintrag erfasst wird.
    var ignoredChangeCount: Int?

    init(pasteboard: NSPasteboard = .general, store: HistoryStore = .shared,
         sourceApplication: @escaping () -> (name: String?, bundleID: String?) = {
             let app = NSWorkspace.shared.frontmostApplication
             return (name: app?.localizedName, bundleID: app?.bundleIdentifier)
         }) {
        self.pasteboard = pasteboard
        self.store = store
        self.sourceApplication = sourceApplication
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

    func setRecordingPaused(_ paused: Bool) {
        guard paused != isRecordingPaused else { return }
        // Consume the final paused change before resuming, even if the timer hasn't
        // fired yet. Keep polling during pause so no paused content is replayed.
        if isRecordingPaused { poll() }
        isRecordingPaused = paused
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
        let source = sourceApplication()
        guard CapturePolicy.shouldSave(types: types.map(\.rawValue), sourceBundleID: source.bundleID,
                                       excludedAppBundleIDs: Settings.excludedAppBundleIDs,
                                       isPaused: isRecordingPaused, ignoreConcealed: Settings.ignoreConcealed) else { return }

        if types.contains(.tiff) || types.contains(Self.pngType),
            let data = pb.data(forType: Self.pngType) ?? pb.data(forType: .tiff) {
            store.addImage(data, sourceAppName: source.name, sourceBundleID: source.bundleID)
        } else if let text = pb.string(forType: .string), !text.isEmpty {
            store.addText(text, sourceAppName: source.name, sourceBundleID: source.bundleID)
        }
    }
}
