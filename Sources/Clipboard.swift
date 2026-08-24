import AppKit

/// Schreibt einen Verlaufseintrag zurück in die Systemzwischenablage.
enum Clipboard {
    static func copyToPasteboard(_ item: HistoryItem) {
        let pb = NSPasteboard.general
        ClipboardMonitor.shared.ignoreNextChange = true
        pb.clearContents()
        switch item.kind {
        case .text:
            pb.setString(item.text ?? "", forType: .string)
        case .image:
            guard let image = HistoryStore.shared.image(for: item),
                  let tiff = image.tiffRepresentation else { return }
            pb.setData(tiff, forType: .tiff)
        }
    }
}
