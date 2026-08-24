import AppKit

extension Notification.Name {
    static let klemmiHistoryDidChange = Notification.Name("KlemmiHistoryDidChange")
}

/// Hält den Zwischenablage-Verlauf im Speicher und auf Platte
/// (~/Library/Application Support/Klemmi). Änderungen werden per
/// Notification gemeldet, damit Popover und Hauptfenster gleichzeitig
/// aktuell bleiben können.
final class HistoryStore {
    static let shared = HistoryStore()

    private(set) var items: [HistoryItem] = []

    private let fm = FileManager.default
    private let imagesDir: URL
    private let indexFile: URL

    private init() {
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let baseDir = support.appendingPathComponent("Klemmi", isDirectory: true)
        imagesDir = baseDir.appendingPathComponent("Images", isDirectory: true)
        indexFile = baseDir.appendingPathComponent("history.json")
        try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: Hinzufügen

    func addText(_ text: String, sourceAppName: String?, sourceBundleID: String?) {
        guard !text.isEmpty else { return }
        if let first = items.first, first.kind == .text, first.text == text { return }
        insert(HistoryItem(id: UUID(), kind: .text, text: text, imageFile: nil,
                            sourceAppName: sourceAppName, sourceBundleID: sourceBundleID, date: Date()))
    }

    func addImage(_ image: NSImage, sourceAppName: String?, sourceBundleID: String?) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        let filename = UUID().uuidString + ".png"
        do { try png.write(to: imagesDir.appendingPathComponent(filename)) } catch { return }
        insert(HistoryItem(id: UUID(), kind: .image, text: nil, imageFile: filename,
                            sourceAppName: sourceAppName, sourceBundleID: sourceBundleID, date: Date()))
    }

    private func insert(_ item: HistoryItem) {
        items.insert(item, at: 0)
        trim()
        save()
        NotificationCenter.default.post(name: .klemmiHistoryDidChange, object: nil)
    }

    private func trim() {
        let max = Settings.maxHistoryItems
        guard items.count > max else { return }
        for old in items.suffix(from: max) {
            if let file = old.imageFile { try? fm.removeItem(at: imagesDir.appendingPathComponent(file)) }
        }
        items = Array(items.prefix(max))
    }

    // MARK: Entfernen

    func delete(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        if let file = items[idx].imageFile { try? fm.removeItem(at: imagesDir.appendingPathComponent(file)) }
        items.remove(at: idx)
        save()
        NotificationCenter.default.post(name: .klemmiHistoryDidChange, object: nil)
    }

    func clear() {
        for item in items {
            if let file = item.imageFile { try? fm.removeItem(at: imagesDir.appendingPathComponent(file)) }
        }
        items = []
        save()
        NotificationCenter.default.post(name: .klemmiHistoryDidChange, object: nil)
    }

    // MARK: Bilder laden

    func image(for item: HistoryItem) -> NSImage? {
        guard let file = item.imageFile else { return nil }
        return NSImage(contentsOf: imagesDir.appendingPathComponent(file))
    }

    // MARK: Persistenz

    private func load() {
        guard let data = try? Data(contentsOf: indexFile) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        items = (try? decoder.decode([HistoryItem].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: indexFile, options: .atomic)
    }
}
