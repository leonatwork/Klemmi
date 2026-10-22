import AppKit

/// Schreibt einen Verlaufseintrag zurück in die Systemzwischenablage.
enum Clipboard {
    @discardableResult
    static func copyToPasteboard(_ item: HistoryItem, pasteboard pb: NSPasteboard = .general,
                                 store: HistoryStore = .shared, monitor: ClipboardMonitor = .shared) -> Bool {
        let payload = NSPasteboardItem()
        switch item.kind {
        case .text:
            guard let text = item.text, payload.setString(text, forType: .string) else {
                NSSound.beep()
                return false
            }
        case .image:
            guard let image = store.image(for: item),
                  let tiff = image.tiffRepresentation,
                  payload.setData(tiff, forType: .tiff) else {
                NSSound.beep()
                return false
            }
        }
        let count = pb.clearContents()
        guard pb.writeObjects([payload]) else {
            monitor.ignoredChangeCount = nil
            NSSound.beep()
            return false
        }
        monitor.ignoredChangeCount = count
        return true
    }
}
