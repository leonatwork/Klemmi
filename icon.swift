import AppKit

// Zeichnet das Klemmi-Symbol (Klemmbrett) und erzeugt daraus ein .icns
func draw(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let s = size
    let rect = NSRect(x: s*0.06, y: s*0.06, width: s*0.88, height: s*0.88)
    let path = NSBezierPath(roundedRect: rect, xRadius: s*0.22, yRadius: s*0.22)

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.10, green: 0.62, blue: 0.55, alpha: 1),
        NSColor(calibratedRed: 0.16, green: 0.42, blue: 0.75, alpha: 1)
    ])!
    gradient.draw(in: path, angle: -90)

    // Klemmbrett
    let board = NSBezierPath(roundedRect: NSRect(x: s*0.30, y: s*0.14, width: s*0.40, height: s*0.62), xRadius: s*0.03, yRadius: s*0.03)
    board.lineWidth = s*0.035
    NSColor.white.setStroke()
    board.stroke()

    // Klammer oben
    NSBezierPath(roundedRect: NSRect(x: s*0.42, y: s*0.70, width: s*0.16, height: s*0.10), xRadius: s*0.02, yRadius: s*0.02)
        .fill()

    // Zeilen
    for y: CGFloat in [0.50, 0.38, 0.26] {
        let line = NSBezierPath()
        line.lineWidth = s*0.035
        line.lineCapStyle = .round
        line.move(to: NSPoint(x: s*0.38, y: s*y))
        line.line(to: NSPoint(x: s*0.62, y: s*y))
        line.stroke()
    }

    img.unlockFocus()
    return img
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Klemmi.iconset")
try? FileManager.default.removeItem(at: tmp)
try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

for (px, name) in [(16,"16x16"),(32,"16x16@2x"),(32,"32x32"),(64,"32x32@2x"),
                   (128,"128x128"),(256,"128x128@2x"),(256,"256x256"),(512,"256x256@2x"),
                   (512,"512x512"),(1024,"512x512@2x")] {
    let img = draw(size: CGFloat(px))
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try! png.write(to: tmp.appendingPathComponent("icon_\(name).png"))
}

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", tmp.path, "-o", out]
try! p.run(); p.waitUntilExit()
