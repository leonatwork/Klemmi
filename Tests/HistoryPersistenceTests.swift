import AppKit

// Only synthetic data, temporary stores and a private pasteboard. Never the real history.
@main
enum HistoryPersistenceTests {
    static let fm = FileManager.default

    static func main() throws {
        let root = fm.temporaryDirectory.appendingPathComponent("KlemmiTests-\(UUID())", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try corruptHistory(root.appendingPathComponent("corrupt"))
        try successfulLoad(root.appendingPathComponent("valid"))
        try failedSaveRetainsImages(root.appendingPathComponent("failed-save"))
        try missingIndexRetainsImages(root.appendingPathComponent("first-launch"))
        try pendingWrites(root.appendingPathComponent("pending"))
        try clipboardWrites(root.appendingPathComponent("clipboard"))
        try privateDirectories(root.appendingPathComponent("permissions"))
        try capturePrivacy(root.appendingPathComponent("privacy"))
    }

    static func prepare(_ base: URL) throws -> URL {
        let images = base.appendingPathComponent("Images", isDirectory: true)
        try fm.createDirectory(at: images, withIntermediateDirectories: true)
        return images
    }

    static func privateDirectories(_ parent: URL) throws {
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: parent.path)
        let base = parent.appendingPathComponent("store", isDirectory: true)
        let images = base.appendingPathComponent("Images", isDirectory: true)
        func permissions(_ directory: URL) throws -> Int {
            let attributes = try fm.attributesOfItem(atPath: directory.path)
            return (attributes[.posixPermissions] as! NSNumber).intValue
        }
        let fresh = HistoryStore(baseDirectory: base)
        fresh.flushPendingWrites()
        try expect(permissions(base) == 0o700)
        try expect(permissions(images) == 0o700)
        // Existing installations must be repaired, without changing parents or data.
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: base.path)
        try fm.setAttributes([.posixPermissions: 0o777], ofItemAtPath: images.path)
        let preserved = Data("synthetic image bytes".utf8)
        let file = images.appendingPathComponent("preserved.png")
        try preserved.write(to: file)
        let existing = HistoryStore(baseDirectory: base)
        existing.flushPendingWrites()
        try expect(permissions(base) == 0o700)
        try expect(permissions(images) == 0o700)
        try expect(permissions(parent) == 0o755)
        try expect(Data(contentsOf: file) == preserved)
    }

    // A normal argument (not precondition's nonthrowing autoclosure) permits disk reads.
    static func expect(_ condition: Bool, file: StaticString = #filePath, line: UInt = #line) {
        precondition(condition, file: file, line: line)
    }

    static func capturePrivacy(_ base: URL) throws {
        let defaults = UserDefaults.standard
        let oldIgnore = defaults.object(forKey: "ignoreConcealed")
        let oldExcluded = defaults.object(forKey: "excludedAppBundleIDs")
        let oldLimit = defaults.object(forKey: "maxHistoryItems")
        defer {
            if let value = oldIgnore { defaults.set(value, forKey: "ignoreConcealed") }
            else { defaults.removeObject(forKey: "ignoreConcealed") }
            if let value = oldExcluded { defaults.set(value, forKey: "excludedAppBundleIDs") }
            else { defaults.removeObject(forKey: "excludedAppBundleIDs") }
            if let value = oldLimit { defaults.set(value, forKey: "maxHistoryItems") }
            else { defaults.removeObject(forKey: "maxHistoryItems") }
        }
        defaults.removeObject(forKey: "ignoreConcealed")
        defaults.removeObject(forKey: "excludedAppBundleIDs")
        Settings.maxHistoryItems = 200
        precondition(Settings.ignoreConcealed)
        precondition(Settings.excludedAppBundleIDs == ["com.apple.keychainaccess", "com.apple.Passwords"])
        let store = HistoryStore(baseDirectory: base)
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        var sourceBundleID = "org.example.editor"
        let monitor = ClipboardMonitor(pasteboard: pb, store: store,
            sourceApplication: { (name: "Synthetic app", bundleID: sourceBundleID) })
        precondition(!monitor.isRecordingPaused)
        func copy(_ text: String, marker: String? = nil, image: Bool = false) {
            pb.clearContents()
            pb.setString(text, forType: .string)
            if image { pb.setData(imageData(), forType: .tiff) }
            if let marker { pb.setData(Data(), forType: NSPasteboard.PasteboardType(rawValue: marker)) }
        }
        func snapshot() throws -> [HistoryItem] {
            store.flushPendingWrites()
            let index = base.appendingPathComponent("history.json")
            return fm.fileExists(atPath: index.path) ? try readItems(base) : []
        }
        for app in ["com.apple.keychainaccess", "com.apple.Passwords"] {
            sourceBundleID = app
            copy("excluded text \(app)")
            monitor.poll()
            copy("excluded image \(app)", image: true)
            monitor.poll()
        }
        try expect(snapshot().isEmpty)
        sourceBundleID = "org.example.custom"
        Settings.excludedAppBundleIDs = [sourceBundleID]
        precondition(defaults.stringArray(forKey: "excludedAppBundleIDs") == [sourceBundleID])
        copy("custom exclusion")
        monitor.poll()
        try expect(snapshot().isEmpty)
        Settings.excludedAppBundleIDs = []
        precondition(Settings.excludedAppBundleIDs.isEmpty)
        copy("allowed after removing exclusion")
        monitor.poll()
        try expect(snapshot().count == 1)
        let markers = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
            "org.nspasteboard.AutoGeneratedType", "com.agilebits.onepassword",
            "de.petermaurer.TransientPasteboardType", "com.typeit4me.clipping"]
        for marker in markers {
            Settings.ignoreConcealed = true
            copy("filtered \(marker)", marker: marker)
            monitor.poll()
            copy("filtered image \(marker)", marker: marker, image: true)
            monitor.poll()
        }
        try expect(snapshot().count == 1)
        Settings.ignoreConcealed = false
        for marker in markers {
            copy("allowed \(marker)", marker: marker)
            monitor.poll()
        }
        let beforePause = try snapshot()
        precondition(beforePause.count == 7)
        monitor.setRecordingPaused(true)
        precondition(monitor.isRecordingPaused)
        copy("paused text")
        monitor.poll()
        copy("paused image", image: true)
        monitor.stopAndCapturePendingChange()
        monitor.setRecordingPaused(false)
        precondition(!monitor.isRecordingPaused)
        monitor.poll()
        try expect(snapshot().map(\.id) == beforePause.map(\.id))
        // Resume must also discard changes made between the last timer tick and the click.
        monitor.setRecordingPaused(true)
        copy("paused without timer tick")
        monitor.setRecordingPaused(false)
        monitor.poll()
        try expect(snapshot().map(\.id) == beforePause.map(\.id))
        // A no-op resume while recording must not swallow a legitimate pending change.
        copy("after resume")
        monitor.setRecordingPaused(false)
        monitor.poll()
        let resumed = try snapshot()
        precondition(resumed.count == 8 && resumed[0].text == "after resume")
        let newMonitor = ClipboardMonitor(pasteboard: pb, store: store)
        precondition(!newMonitor.isRecordingPaused)
        let files = try fm.contentsOfDirectory(atPath: base.appendingPathComponent("Images").path)
        precondition(files.isEmpty) // Rejected images must never reach disk.
    }

    static func readItems(_ base: URL) throws -> [HistoryItem] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([HistoryItem].self, from: Data(contentsOf: base.appendingPathComponent("history.json")))
    }

    static func corruptHistory(_ base: URL) throws {
        let images = try prepare(base)
        let broken = Data("[{broken synthetic history".utf8)
        let olderBackup = Data("older synthetic backup".utf8)
        try broken.write(to: base.appendingPathComponent("history.json"))
        try olderBackup.write(to: base.appendingPathComponent("history.json.corrupt"))
        try Data([1, 2, 3]).write(to: images.appendingPathComponent("keep.png"))
        let store = HistoryStore(baseDirectory: base)
        store.addText("new synthetic entry", sourceAppName: nil, sourceBundleID: nil)
        store.flushPendingWrites()
        let names = try fm.contentsOfDirectory(atPath: base.path)
        let backups = names.filter { $0.hasPrefix("history.json.corrupt.") }
        precondition(backups.count == 1)
        let preserved = try Data(contentsOf: base.appendingPathComponent(backups[0]))
        let older = try Data(contentsOf: base.appendingPathComponent("history.json.corrupt"))
        precondition(preserved == broken && older == olderBackup)
        let saved = try readItems(base)
        precondition(saved.first?.text == "new synthetic entry")
        store.clear()
        store.flushPendingWrites()
        precondition(fm.fileExists(atPath: images.appendingPathComponent("keep.png").path))
    }

    static func successfulLoad(_ base: URL) throws {
        let images = try prepare(base)
        let kept = HistoryItem(id: UUID(), kind: .image, text: nil, imageFile: "used.png", sourceAppName: nil, sourceBundleID: nil, date: Date())
        let missing = HistoryItem(id: UUID(), kind: .image, text: nil, imageFile: "missing.png", sourceAppName: nil, sourceBundleID: nil, date: Date())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([kept, missing]).write(to: base.appendingPathComponent("history.json"))
        try Data([1]).write(to: images.appendingPathComponent("used.png"))
        try Data([2]).write(to: images.appendingPathComponent("orphan.png"))
        let store = HistoryStore(baseDirectory: base)
        store.flushPendingWrites()
        precondition(store.items.count == 2) // Missing images remain visible.
        precondition(fm.fileExists(atPath: images.appendingPathComponent("used.png").path))
        precondition(!fm.fileExists(atPath: images.appendingPathComponent("orphan.png").path))
    }

    static func pendingWrites(_ base: URL) throws {
        _ = try prepare(base)
        let data = imageData()
        let store = HistoryStore(baseDirectory: base)
        store.addImage(data, sourceAppName: nil, sourceBundleID: nil)
        store.addText("after image", sourceAppName: nil, sourceBundleID: nil)
        // Block the main thread exactly as termination does: no run-loop callbacks.
        store.flushPendingWrites()
        let saved = try readItems(base)
        precondition(saved.count == 2 && saved[0].text == "after image" && saved[1].kind == .image)
        let imageURL = base.appendingPathComponent("Images").appendingPathComponent(saved[1].imageFile!)
        precondition(NSImage(contentsOf: imageURL) != nil)
        let reloaded = HistoryStore(baseDirectory: base)
        reloaded.flushPendingWrites()
        precondition(reloaded.items.map(\.id) == saved.map(\.id))
        // Clear is ordered after a pending image and cannot resurrect it later.
        store.addImage(data, sourceAppName: nil, sourceBundleID: nil)
        store.clear()
        store.flushPendingWrites()
        let cleared = try readItems(base)
        let files = try fm.contentsOfDirectory(atPath: base.appendingPathComponent("Images").path)
        precondition(cleared.isEmpty && files.isEmpty)
    }

    static func imageData() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<8 { for x in 0..<8 { rep.setColor(.red, atX: x, y: y) } }
        return rep.representation(using: .tiff, properties: [:])!
    }

    static func failedSaveRetainsImages(_ base: URL) throws {
        _ = try prepare(base)
        let store = HistoryStore(baseDirectory: base)
        store.addImage(imageData(), sourceAppName: nil, sourceBundleID: nil)
        store.flushPendingWrites()
        let saved = try readItems(base)
        let index = base.appendingPathComponent("history.json")
        let previous = base.appendingPathComponent("previous.json")
        try fm.moveItem(at: index, to: previous)
        // A directory at the index path causes a deterministic write failure.
        try fm.createDirectory(at: index, withIntermediateDirectories: false)
        store.delete(saved[0].id)
        store.flushPendingWrites()
        let imageURL = base.appendingPathComponent("Images").appendingPathComponent(saved[0].imageFile!)
        precondition(fm.fileExists(atPath: imageURL.path))
        try fm.removeItem(at: index)
        try fm.moveItem(at: previous, to: index)
        let reloaded = HistoryStore(baseDirectory: base)
        reloaded.flushPendingWrites()
        precondition(reloaded.items.first?.id == saved[0].id && reloaded.image(for: saved[0]) != nil)
    }

    static func missingIndexRetainsImages(_ base: URL) throws {
        let images = try prepare(base)
        let existing = images.appendingPathComponent("unknown.png")
        try Data([1]).write(to: existing)
        let store = HistoryStore(baseDirectory: base)
        store.addText("first launch", sourceAppName: nil, sourceBundleID: nil)
        store.flushPendingWrites()
        precondition(fm.fileExists(atPath: existing.path))
        let names = try fm.contentsOfDirectory(atPath: base.path)
        precondition(!names.contains { $0.hasPrefix("history.json.corrupt") })
    }

    static func clipboardWrites(_ base: URL) throws {
        let store = HistoryStore(baseDirectory: base)
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        let monitor = ClipboardMonitor(pasteboard: pb, store: store)
        let own = HistoryItem(id: UUID(), kind: .text, text: "own synthetic text", imageFile: nil, sourceAppName: nil, sourceBundleID: nil, date: Date())
        precondition(Clipboard.copyToPasteboard(own, pasteboard: pb, store: store, monitor: monitor))
        monitor.poll()
        store.flushPendingWrites()
        precondition(!fm.fileExists(atPath: base.appendingPathComponent("history.json").path))

        precondition(Clipboard.copyToPasteboard(own, pasteboard: pb, store: store, monitor: monitor))
        pb.clearContents()
        pb.setString("foreign synthetic text", forType: .string)
        monitor.poll()
        store.flushPendingWrites()
        let captured = try readItems(base)
        precondition(captured.count == 1 && captured[0].text == "foreign synthetic text")

        let missing = HistoryItem(id: UUID(), kind: .image, text: nil, imageFile: "missing.png", sourceAppName: nil, sourceBundleID: nil, date: Date())
        let before = pb.changeCount
        precondition(!Clipboard.copyToPasteboard(missing, pasteboard: pb, store: store, monitor: monitor))
        precondition(pb.changeCount == before && pb.string(forType: .string) == "foreign synthetic text")
        precondition(monitor.ignoredChangeCount == nil)
        pb.clearContents()
        pb.setString("copy just before quit", forType: .string)
        monitor.stopAndCapturePendingChange()
        store.flushPendingWrites()
        let onQuit = try readItems(base)
        precondition(onQuit.first?.text == "copy just before quit")

        pb.clearContents()
        pb.setData(imageData(), forType: .tiff)
        monitor.stopAndCapturePendingChange()
        store.flushPendingWrites()
        let imageOnQuit = try readItems(base)
        precondition(imageOnQuit.first?.kind == .image)
        precondition(store.image(for: imageOnQuit[0]) != nil)
        // Restoring a valid image is ignored as well as restoring text.
        precondition(Clipboard.copyToPasteboard(imageOnQuit[0], pasteboard: pb, store: store, monitor: monitor))
        monitor.poll()
        store.flushPendingWrites()
        let afterRestore = try readItems(base)
        precondition(afterRestore.map(\.id) == imageOnQuit.map(\.id))
    }
}
