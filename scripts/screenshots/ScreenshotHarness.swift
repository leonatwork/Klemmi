import AppKit

// Renders the README screenshots offscreen from invented demo data.
//
// Compiled together with Sources/*.swift (without main.swift) by render.sh and run inside a
// temporary .app bundle so the .lproj localizations apply. The harness
//   - points HistoryStore at a fresh demo directory (never ~/Library/Application Support/Klemmi),
//   - never starts ClipboardMonitor and never touches NSPasteboard,
//   - never puts a window on screen and never captures the screen: every view is drawn
//     with cacheDisplay(in:to:) into an in-memory bitmap at 2× scale.
//
// Usage: KlemmiScreenshots -data <empty demo dir> -out <dir> -lang <en|de>

@main
enum ScreenshotHarness {
    static let scale: CGFloat = 2

    static func main() {
        let args = UserDefaults.standard
        guard let dataPath = args.string(forKey: "data"), let outPath = args.string(forKey: "out"),
              let lang = args.string(forKey: "lang") else {
            fail("usage: KlemmiScreenshots -data <dir> -out <dir> -lang <en|de>")
        }
        let dataDir = URL(fileURLWithPath: dataPath, isDirectory: true).standardizedFileURL
        let outDir = URL(fileURLWithPath: outPath, isDirectory: true).standardizedFileURL
        let suffix = lang == "en" ? "" : ".\(lang)"

        // Never let the demo store land in (or next to) the real history.
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].standardizedFileURL
        guard !dataDir.path.hasPrefix(library.path) else { fail("refusing demo data dir inside ~/Library") }

        let demo = DemoData(lang: lang)
        demo.write(to: dataDir)

        // Volatile defaults only: overview grouped by app. Nothing is persisted.
        UserDefaults.standard.register(defaults: ["groupingMode": GroupingMode.app.rawValue])

        HistoryStore.baseDirectoryOverride = dataDir
        guard HistoryStore.shared.items.count == demo.entries.count else {
            fail("demo store did not load (\(HistoryStore.shared.items.count) items)")
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.appearance = NSAppearance(named: .aqua)

        do {
            try write(renderPopover(), to: outDir.appendingPathComponent("popover\(suffix).png"))
            try write(renderOverview(), to: outDir.appendingPathComponent("overview\(suffix).png"))
            try write(renderOverlay(), to: outDir.appendingPathComponent("overlay\(suffix).png"))
        } catch {
            fail("could not write PNG: \(error)")
        }

        // setFrameAutosaveName in MainWindowController stores a frame in the harness's own
        // defaults domain; drop it so the harness leaves nothing behind.
        if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
        exit(1)
    }

    // MARK: Shots

    /// Menu bar popover: the HistoryListController as StatusItemController shows it.
    static func renderPopover() -> CGImage {
        let list = HistoryListController()
        let host = offscreenWindow(for: list.view)
        settle(host)
        let ui = snapshot(list.view)
        let size = list.view.bounds.size

        let padding: CGFloat = 40, menuBar: CGFloat = 26, arrow: CGFloat = 10
        let canvas = NSSize(width: size.width + 2 * padding, height: size.height + menuBar + arrow + 18 + padding)
        return composite(canvas) { _ in
            let iconX = padding + size.width / 2
            drawMenuBar(width: canvas.width, height: menuBar, top: canvas.height, klemmiX: iconX)

            let body = NSRect(x: padding, y: padding, width: size.width, height: size.height)
            let shape = popoverShape(body, arrowX: iconX, arrowHeight: arrow)
            withShadow { NSColor(white: 0.975, alpha: 1).setFill(); shape.fill() }
            NSColor(white: 0, alpha: 0.12).setStroke()
            shape.lineWidth = 0.5
            shape.stroke()
            draw(ui, in: body)
        }
    }

    /// Overview window, grouped by source app, including the title bar.
    static func renderOverview() -> CGImage {
        let controller = MainWindowController()
        guard let window = controller.window, let content = window.contentView else { fail("no window") }
        window.appearance = NSAppearance(named: .aqua)
        window.setContentSize(NSSize(width: 440, height: 672))
        settle(window)

        let contentImage = snapshot(content)
        let size = content.bounds.size
        let titleBar: CGFloat = 32, padding: CGFloat = 48, radius: CGFloat = 12
        let windowRect = NSRect(x: padding, y: padding, width: size.width, height: size.height + titleBar)
        let canvas = NSSize(width: size.width + 2 * padding, height: windowRect.height + 2 * padding)
        return composite(canvas) { _ in
            let frame = NSBezierPath(roundedRect: windowRect, xRadius: radius, yRadius: radius)
            withShadow { NSColor.windowBackgroundColor.setFill(); frame.fill() }
            NSGraphicsContext.saveGraphicsState()
            frame.addClip()
            draw(contentImage, in: NSRect(x: windowRect.minX, y: windowRect.minY, width: size.width, height: size.height))
            drawTitleBar(NSRect(x: windowRect.minX, y: windowRect.maxY - titleBar, width: windowRect.width, height: titleBar),
                         title: window.title)
            NSGraphicsContext.restoreGraphicsState()
            NSColor(white: 0, alpha: 0.18).setStroke()
            frame.lineWidth = 0.5
            frame.stroke()
        }
    }

    /// The ⌘⇧C overlay panel with the first entry preselected, as right after opening it
    /// (focus stays in the search field, so the selection is not emphasised).
    static func renderOverlay() -> CGImage {
        let overlay = OverlayController()
        guard let panel = NSApp.windows.first(where: { String(describing: type(of: $0)).contains("OverlayPanel") }),
              let content = panel.contentView else { fail("overlay panel not found") }
        panel.appearance = NSAppearance(named: .aqua)
        settle(panel)
        // Offscreen, the row view paints the unemphasised selection as an opaque black
        // material. Take the selection out of the table and paint it ourselves behind the
        // list, in the colour AppKit uses while the search field keeps the focus.
        var selection: NSRect?
        if let table = subviews(of: content, ofType: NSTableView.self).first, table.selectedRow >= 0 {
            let row = table.rowView(atRow: table.selectedRow, makeIfNecessary: true)
            selection = row.map { $0.convert($0.bounds, to: content) }
            table.deselectAll(nil)
            settle(panel)
        }
        // The content view is an NSVisualEffectView, which renders an opaque grey fallback
        // offscreen. Draw its subviews (title, hint, list) individually on our own background.
        let parts = content.subviews.map { ($0.frame, snapshot($0)) }
        withExtendedLifetime(overlay) {}
        let size = content.bounds.size

        let padding: CGFloat = 48
        let canvas = NSSize(width: size.width + 2 * padding, height: size.height + 2 * padding)
        return composite(canvas) { _ in
            let body = NSRect(x: padding, y: padding, width: size.width, height: size.height)
            let shape = NSBezierPath(roundedRect: body, xRadius: 12, yRadius: 12)
            withShadow { NSColor(white: 0.975, alpha: 1).setFill(); shape.fill() }
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            if let selection {
                NSColor.unemphasizedSelectedContentBackgroundColor.setFill()
                NSBezierPath(roundedRect: selection.insetBy(dx: 10, dy: 0).offsetBy(dx: body.minX, dy: body.minY),
                             xRadius: 6, yRadius: 6).fill()
            }
            for (frame, image) in parts { draw(image, in: frame.offsetBy(dx: body.minX, dy: body.minY)) }
            NSGraphicsContext.restoreGraphicsState()
            NSColor(white: 0, alpha: 0.14).setStroke()
            shape.lineWidth = 0.5
            shape.stroke()
        }
    }

    // MARK: Offscreen rendering

    static func offscreenWindow(for view: NSView) -> NSWindow {
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.isReleasedWhenClosed = false
        window.contentView = view
        return window
    }

    /// Lays the window out and lets table views create their rows, without ordering it in.
    static func settle(_ window: NSWindow) {
        for _ in 0..<3 {
            window.contentView?.layoutSubtreeIfNeeded()
            window.layoutIfNeeded()
            window.displayIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }

    static func snapshot(_ view: NSView) -> NSBitmapImageRep {
        let size = view.bounds.size
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                   pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        view.appearance = NSAppearance(named: .aqua)
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: view.bounds, to: rep)
        }
        return rep
    }

    static func subviews<T: NSView>(of view: NSView, ofType: T.Type) -> [T] {
        view.subviews.flatMap { sub -> [T] in ((sub as? T).map { [$0] } ?? []) + subviews(of: sub, ofType: T.self) }
    }

    // MARK: Compositing

    /// Draws into a 2× bitmap on a soft neutral backdrop with rounded corners, so the
    /// image reads well on GitHub's light and dark themes.
    static func composite(_ size: NSSize, _ body: (NSSize) -> Void) -> CGImage {
        let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            let backdrop = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 20, yRadius: 20)
            NSGradient(starting: NSColor(srgbRed: 0.925, green: 0.937, blue: 0.953, alpha: 1),
                       ending: NSColor(srgbRed: 0.871, green: 0.890, blue: 0.918, alpha: 1))!
                .draw(in: backdrop, angle: -90)
            body(size)
        }
        NSGraphicsContext.current = previous
        return ctx.makeImage()!
    }

    static func withShadow(_ draw: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.22)
        shadow.shadowBlurRadius = 22
        shadow.shadowOffset = NSSize(width: 0, height: -8)
        shadow.set()
        draw()
        NSGraphicsContext.restoreGraphicsState()
    }

    static func draw(_ rep: NSBitmapImageRep, in rect: NSRect) {
        rep.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
    }

    /// Popover body with the arrow pointing up at the menu bar icon.
    static func popoverShape(_ body: NSRect, arrowX: CGFloat, arrowHeight: CGFloat) -> NSBezierPath {
        let r: CGFloat = 12, half: CGFloat = 11
        let path = NSBezierPath()
        path.move(to: NSPoint(x: body.minX + r, y: body.minY))
        path.line(to: NSPoint(x: body.maxX - r, y: body.minY))
        path.appendArc(withCenter: NSPoint(x: body.maxX - r, y: body.minY + r), radius: r, startAngle: 270, endAngle: 360)
        path.line(to: NSPoint(x: body.maxX, y: body.maxY - r))
        path.appendArc(withCenter: NSPoint(x: body.maxX - r, y: body.maxY - r), radius: r, startAngle: 0, endAngle: 90)
        path.line(to: NSPoint(x: arrowX + half, y: body.maxY))
        path.curve(to: NSPoint(x: arrowX, y: body.maxY + arrowHeight),
                   controlPoint1: NSPoint(x: arrowX + half * 0.45, y: body.maxY),
                   controlPoint2: NSPoint(x: arrowX + 2, y: body.maxY + arrowHeight))
        path.curve(to: NSPoint(x: arrowX - half, y: body.maxY),
                   controlPoint1: NSPoint(x: arrowX - 2, y: body.maxY + arrowHeight),
                   controlPoint2: NSPoint(x: arrowX - half * 0.45, y: body.maxY))
        path.line(to: NSPoint(x: body.minX + r, y: body.maxY))
        path.appendArc(withCenter: NSPoint(x: body.minX + r, y: body.maxY - r), radius: r, startAngle: 90, endAngle: 180)
        path.line(to: NSPoint(x: body.minX, y: body.minY + r))
        path.appendArc(withCenter: NSPoint(x: body.minX + r, y: body.minY + r), radius: r, startAngle: 180, endAngle: 270)
        path.close()
        return path
    }

    /// A strip of the menu bar with Klemmi's icon (highlighted) and a few system symbols.
    static func drawMenuBar(width: CGFloat, height: CGFloat, top: CGFloat, klemmiX: CGFloat) {
        let bar = NSRect(x: 0, y: top - height, width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: top), xRadius: 20, yRadius: 20).addClip()
        NSColor(white: 1, alpha: 0.7).setFill()
        bar.fill()
        NSGraphicsContext.restoreGraphicsState()

        let highlight = NSRect(x: klemmiX - 15, y: bar.minY + 3, width: 30, height: height - 6)
        NSColor(white: 0, alpha: 0.1).setFill()
        NSBezierPath(roundedRect: highlight, xRadius: 6, yRadius: 6).fill()
        tinted(menuBarIcon(), .labelColor).draw(in: NSRect(x: klemmiX - 9, y: bar.midY - 9, width: 18, height: 18))

        var x = klemmiX + 34
        for name in ["wifi", "battery.100percent", "magnifyingglass", "switch.2"] {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) else { continue }
            let s = symbol.size
            tinted(symbol, .labelColor).draw(in: NSRect(x: x, y: bar.midY - s.height / 2, width: s.width, height: s.height))
            x += s.width + 16
        }
    }

    /// Same drawing as StatusItemController.menuBarIcon().
    static func menuBarIcon() -> NSImage {
        NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let s: CGFloat = 18
            NSColor.black.set()
            let board = NSBezierPath(roundedRect: NSRect(x: s*0.2, y: s*0.06, width: s*0.6, height: s*0.84), xRadius: 2, yRadius: 2)
            board.lineWidth = 1.4
            board.stroke()
            NSBezierPath(roundedRect: NSRect(x: s*0.38, y: s*0.80, width: s*0.24, height: s*0.14), xRadius: 1.5, yRadius: 1.5).fill()
            for y: CGFloat in [0.60, 0.45, 0.30] {
                let line = NSBezierPath()
                line.lineWidth = 1.2
                line.move(to: NSPoint(x: s*0.32, y: s*y))
                line.line(to: NSPoint(x: s*0.68, y: s*y))
                line.stroke()
            }
            return true
        }
    }

    static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    /// Title bar with traffic lights and centred title, as AppKit draws it for a titled window.
    static func drawTitleBar(_ rect: NSRect, title: String) {
        NSColor(white: 0.985, alpha: 1).setFill()
        rect.fill()
        NSColor(white: 0, alpha: 0.08).setFill()
        NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 0.5).fill()

        let colors: [NSColor] = [
            NSColor(srgbRed: 1.00, green: 0.37, blue: 0.34, alpha: 1),
            NSColor(srgbRed: 1.00, green: 0.74, blue: 0.18, alpha: 1),
            NSColor(srgbRed: 0.16, green: 0.79, blue: 0.25, alpha: 1),
        ]
        for (i, color) in colors.enumerated() {
            let dot = NSRect(x: rect.minX + 13 + CGFloat(i) * 20, y: rect.midY - 6, width: 12, height: 12)
            color.setFill()
            NSBezierPath(ovalIn: dot).fill()
            NSColor(white: 0, alpha: 0.12).setStroke()
            NSBezierPath(ovalIn: dot.insetBy(dx: 0.25, dy: 0.25)).stroke()
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        let text = NSAttributedString(string: title, attributes: attrs)
        let s = text.size()
        text.draw(at: NSPoint(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2))
    }

    static func write(_ image: CGImage, to url: URL) throws {
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        guard let png = rep.representation(using: .png, properties: [:]) else { fail("PNG encoding failed") }
        try png.write(to: url)
        print("wrote \(url.lastPathComponent) (\(image.width)×\(image.height), \(png.count / 1024) KB)")
    }
}

// MARK: Demo data

/// Invented, neutral entries attributed to common Apple apps. Nothing here comes from a
/// real clipboard.
struct DemoData {
    struct Entry {
        let text: String?
        let app: String
        let bundleID: String
        let minutesAgo: Double
    }

    let entries: [Entry]

    init(lang: String) {
        let de = lang == "de"
        let messages = de ? "Nachrichten" : "Messages"
        let notes = de ? "Notizen" : "Notes"
        let preview = de ? "Vorschau" : "Preview"
        entries = [
            Entry(text: "https://developer.apple.com/documentation/appkit", app: "Safari",
                  bundleID: "com.apple.Safari", minutesAgo: 1),
            Entry(text: de ? "Meeting auf 15 Uhr verschoben" : "Meeting moved to 3 pm", app: messages,
                  bundleID: "com.apple.MobileSMS", minutesAgo: 3),
            Entry(text: de ? "let greeting = \"Hallo, Welt!\"\nprint(greeting)" : "let greeting = \"Hello, world!\"\nprint(greeting)",
                  app: "TextEdit", bundleID: "com.apple.TextEdit", minutesAgo: 8),
            Entry(text: de ? "Lissabon, Portugal" : "Lisbon, Portugal", app: notes,
                  bundleID: "com.apple.Notes", minutesAgo: 15),
            Entry(text: nil, app: preview, bundleID: "com.apple.Preview", minutesAgo: 26),
            Entry(text: "https://www.swift.org/getting-started/", app: "Safari",
                  bundleID: "com.apple.Safari", minutesAgo: 42),
            Entry(text: de ? "Einkaufsliste: Hafermilch, Äpfel, Kaffeebohnen" : "Shopping list: oat milk, apples, coffee beans",
                  app: notes, bundleID: "com.apple.Notes", minutesAgo: 65),
            Entry(text: de ? "Klingt gut, bis später!" : "Sounds good, see you there!", app: messages,
                  bundleID: "com.apple.MobileSMS", minutesAgo: 95),
            Entry(text: de ? "https://de.wikipedia.org/wiki/Lissabon" : "https://en.wikipedia.org/wiki/Lisbon",
                  app: "Safari", bundleID: "com.apple.Safari", minutesAgo: 150),
            Entry(text: de ? "Versionshinweise: schnellere Suche, weniger Speicherbedarf"
                           : "Release notes: faster search, smaller memory footprint",
                  app: "TextEdit", bundleID: "com.apple.TextEdit", minutesAgo: 210),
        ]
    }

    /// Writes history.json plus the demo image into a fresh directory, in the store's format.
    func write(to dir: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: dir)
        let images = dir.appendingPathComponent("Images", isDirectory: true)
        try! fm.createDirectory(at: images, withIntermediateDirectories: true)

        let now = Date()
        let items: [HistoryItem] = entries.map { e in
            var file: String?
            if e.text == nil {
                file = "demo-chart.png"
                try! Self.chartPNG().write(to: images.appendingPathComponent(file!))
            }
            return HistoryItem(id: UUID(), kind: e.text == nil ? .image : .text, text: e.text, imageFile: file,
                               sourceAppName: e.app, sourceBundleID: e.bundleID,
                               date: now.addingTimeInterval(-e.minutesAgo * 60))
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try! encoder.encode(items).write(to: dir.appendingPathComponent("history.json"))
    }

    /// A small bar chart on a gradient, drawn here so no real image is involved.
    static func chartPNG() -> Data {
        let size = NSSize(width: 240, height: 240)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(starting: NSColor(srgbRed: 0.36, green: 0.55, blue: 0.98, alpha: 1),
                       ending: NSColor(srgbRed: 0.62, green: 0.38, blue: 0.93, alpha: 1))!
                .draw(in: NSBezierPath(roundedRect: rect, xRadius: 36, yRadius: 36), angle: -45)
            NSColor(white: 1, alpha: 0.92).setFill()
            for (i, h) in [0.35, 0.6, 0.45, 0.8].enumerated() {
                let bar = NSRect(x: 40 + CGFloat(i) * 44, y: 40, width: 28, height: 160 * h)
                NSBezierPath(roundedRect: bar, xRadius: 6, yRadius: 6).fill()
            }
            return true
        }
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return rep.representation(using: .png, properties: [:])!
    }
}
