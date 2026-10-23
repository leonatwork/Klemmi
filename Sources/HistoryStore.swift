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

    /// Alternativer Speicherort statt ~/Library/Application Support/Klemmi. Nur für
    /// Werkzeuge wie scripts/screenshots, die mit Demo-Daten arbeiten; die App setzt ihn
    /// nie. Muss vor dem ersten Zugriff auf `shared` gesetzt werden.
    static var baseDirectoryOverride: URL?

    private(set) var items: [HistoryItem] = []

    private let fm = FileManager.default
    private let imagesDir: URL
    private let indexFile: URL
    private let queue = DispatchQueue(label: "de.local.klemmi.history", qos: .utility)

    // After initialization these belong exclusively to queue. UI state and
    // notifications stay on main; disk completion never depends on a main callback.
    private var storedItems: [HistoryItem] = []
    private var loadFailed = false
    private var canSave = true
    private var pendingImageRemovals: Set<String> = []

    private convenience init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let baseDir = Self.baseDirectoryOverride
            ?? support.appendingPathComponent("Klemmi", isDirectory: true)
        self.init(baseDirectory: baseDir)
    }

    /// Explicit directory for isolated tests; never changes the shared store.
    init(baseDirectory: URL) {
        imagesDir = baseDirectory.appendingPathComponent("Images", isDirectory: true)
        indexFile = baseDirectory.appendingPathComponent("history.json")
        do {
            try fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        } catch {
            NSLog("Klemmi: cannot create history directory (error %ld)", (error as NSError).code)
        }
        load()
        items = storedItems
    }

    // MARK: Hinzufügen

    func addText(_ text: String, sourceAppName: String?, sourceBundleID: String?) {
        precondition(Thread.isMainThread)
        guard !text.isEmpty else { return }
        let item = HistoryItem(id: UUID(), kind: .text, text: text, imageFile: nil,
                               sourceAppName: sourceAppName, sourceBundleID: sourceBundleID, date: Date())
        let limit = Settings.maxHistoryItems
        queue.async {
            if let first = self.storedItems.first, first.kind == .text, first.text == text { return }
            self.insert(item, limit: limit)
        }
    }

    /// Capture pasteboard bytes on main; decoding and PNG encoding happen on queue.
    func addImage(_ data: Data, sourceAppName: String?, sourceBundleID: String?) {
        precondition(Thread.isMainThread)
        let filename = UUID().uuidString + ".png"
        let item = HistoryItem(id: UUID(), kind: .image, text: nil, imageFile: filename,
                               sourceAppName: sourceAppName, sourceBundleID: sourceBundleID, date: Date())
        let limit = Settings.maxHistoryItems
        queue.async {
            autoreleasepool {
                guard self.canSave else { return }
                guard let rep = NSBitmapImageRep(data: data),
                      let png = rep.representation(using: .png, properties: [:]) else {
                    NSLog("Klemmi: cannot encode clipboard image")
                    return
                }
                do {
                    try png.write(to: self.imagesDir.appendingPathComponent(filename), options: .atomic)
                } catch {
                    NSLog("Klemmi: cannot save clipboard image (error %ld)", (error as NSError).code)
                    return
                }
                self.insert(item, limit: limit)
            }
        }
    }

    private func insert(_ item: HistoryItem, limit: Int) {
        storedItems.insert(item, at: 0)
        if storedItems.count > limit {
            pendingImageRemovals.formUnion(storedItems.suffix(from: limit).compactMap(\.imageFile))
            storedItems = Array(storedItems.prefix(limit))
        }
        save()
        publish()
    }

    private func publish() {
        let snapshot = storedItems
        DispatchQueue.main.async {
            self.items = snapshot
            NotificationCenter.default.post(name: .klemmiHistoryDidChange, object: nil)
        }
    }

    // MARK: Entfernen

    func delete(_ id: UUID) {
        precondition(Thread.isMainThread)
        queue.async {
            guard let idx = self.storedItems.firstIndex(where: { $0.id == id }) else { return }
            if let file = self.storedItems[idx].imageFile { self.pendingImageRemovals.insert(file) }
            self.storedItems.remove(at: idx)
            self.save()
            self.publish()
        }
    }

    func clear() {
        precondition(Thread.isMainThread)
        queue.async {
            self.pendingImageRemovals.formUnion(self.storedItems.compactMap(\.imageFile))
            self.storedItems = []
            self.save()
            self.publish()
        }
    }

    // MARK: Bilder laden

    func image(for item: HistoryItem) -> NSImage? {
        guard let file = item.imageFile else { return nil }
        return NSImage(contentsOf: imagesDir.appendingPathComponent(file))
    }

    // MARK: Persistenz

    private func load() {
        let data: Data
        do {
            data = try Data(contentsOf: indexFile)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError { return }
            loadFailed = true
            canSave = false // An unreadable original must never be overwritten.
            NSLog("Klemmi: cannot read history; saving disabled (error %ld)", nsError.code)
            return
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            storedItems = try decoder.decode([HistoryItem].self, from: data)
        } catch {
            loadFailed = true
            do {
                let base = indexFile.deletingLastPathComponent()
                let existing = Set(try fm.contentsOfDirectory(atPath: base.path))
                let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
                let name = HistorySafety.backupName(existing: existing, timestamp: timestamp)
                // copyItem refuses to replace an existing backup, even on a collision.
                try fm.copyItem(at: indexFile, to: base.appendingPathComponent(name))
                NSLog("Klemmi: undecodable history preserved as %@", name)
            } catch {
                canSave = false
                NSLog("Klemmi: cannot back up history; saving disabled (error %ld)", (error as NSError).code)
            }
            return
        }
        // Only a decoded index authorizes startup orphan cleanup. Missing index and
        // all load failures leave Images untouched.
        let referenced = Set(storedItems.compactMap(\.imageFile))
        queue.async {
            do {
                let urls = try self.fm.contentsOfDirectory(at: self.imagesDir, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                let files = try urls.filter {
                    let values = try $0.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    return values.isRegularFile == true && values.isSymbolicLink != true
                }
                self.removeImages(HistorySafety.orphanedFiles(existing: Set(files.map(\.lastPathComponent)), referenced: referenced))
            } catch {
                NSLog("Klemmi: cannot enumerate orphan images (error %ld)", (error as NSError).code)
            }
        }
    }

    private func save() {
        guard canSave else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(storedItems)
            try data.write(to: indexFile, options: .atomic)
            // Delete only after the new index is durable. A failed save retains all
            // images referenced by the previous index. AC-7 protects the whole session.
            if !loadFailed {
                let referenced = Set(storedItems.compactMap(\.imageFile))
                removeImages(HistorySafety.orphanedFiles(existing: pendingImageRemovals, referenced: referenced))
                pendingImageRemovals.removeAll()
            }
        } catch {
            NSLog("Klemmi: cannot save history (error %ld)", (error as NSError).code)
        }
    }

    private func removeImages(_ files: Set<String>) {
        for file in files {
            do {
                try fm.removeItem(at: imagesDir.appendingPathComponent(file))
            } catch {
                NSLog("Klemmi: cannot remove unused image (error %ld)", (error as NSError).code)
            }
        }
    }

    /// No worker ever waits on main, so termination can safely drain all writes.
    func flushPendingWrites() {
        precondition(Thread.isMainThread)
        queue.sync {}
    }
}
