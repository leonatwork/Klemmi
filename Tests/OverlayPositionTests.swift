import CoreGraphics

// Ausfuehrung auf macOS (ohne Testtarget):
// swiftc Sources/OverlayPositioning.swift Tests/OverlayPositionTests.swift -o /tmp/OverlayPositionTests && /tmp/OverlayPositionTests

private func assertPoint(
    _ actual: CGPoint,
    equals expected: CGPoint,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    precondition(actual == expected, "expected \(expected), got \(actual)", file: file, line: line)
}

private func runOverlayOriginTests() {
    let visibleFrame = CGRect(x: 100, y: 100, width: 1000, height: 700)
    let size = CGSize(width: 420, height: 480)

    // Standardfall: linke obere Ecke am Mauszeiger.
    assertPoint(
        OverlayPositioning.overlayOrigin(mouse: CGPoint(x: 300, y: 700), visibleFrame: visibleFrame, size: size),
        equals: CGPoint(x: 300, y: 220)
    )

    // Rechts über Rand: horizontal spiegeln.
    assertPoint(
        OverlayPositioning.overlayOrigin(mouse: CGPoint(x: 1080, y: 700), visibleFrame: visibleFrame, size: size),
        equals: CGPoint(x: 660, y: 220)
    )

    // Unten über Rand: vertikal spiegeln.
    assertPoint(
        OverlayPositioning.overlayOrigin(mouse: CGPoint(x: 300, y: 140), visibleFrame: visibleFrame, size: size),
        equals: CGPoint(x: 300, y: 140)
    )

    // Rechts unten über Rand: auf beiden Achsen spiegeln.
    assertPoint(
        OverlayPositioning.overlayOrigin(mouse: CGPoint(x: 1080, y: 140), visibleFrame: visibleFrame, size: size),
        equals: CGPoint(x: 660, y: 140)
    )

    // Nach Spiegeln immer noch außerhalb: links/oben in sichtbaren Bereich schieben.
    let tinyFrame = CGRect(x: 0, y: 0, width: 320, height: 250)
    assertPoint(
        OverlayPositioning.overlayOrigin(mouse: CGPoint(x: 310, y: 10), visibleFrame: tinyFrame, size: size),
        equals: CGPoint(x: 0, y: 0)
    )

    // Negativer Ursprung (Sekundärbildschirm) + Mauspunkt außerhalb: robust clampen.
    let secondaryVisibleFrame = CGRect(x: -1920, y: 0, width: 1720, height: 900)
    assertPoint(
        OverlayPositioning.overlayOrigin(mouse: CGPoint(x: -1950, y: 950), visibleFrame: secondaryVisibleFrame, size: size),
        equals: CGPoint(x: -1920, y: 420)
    )
}

private func runCenteredOriginTests() {
    let visibleFrame = CGRect(x: 50, y: 40, width: 1001, height: 701)
    let size = CGSize(width: 420, height: 480)

    // Fallback mittig auf NSScreen.main.visibleFrame (mit Rundung wie im Produktivcode).
    assertPoint(
        OverlayPositioning.centeredOrigin(visibleFrame: visibleFrame, size: size),
        equals: CGPoint(x: 341, y: 151)
    )
}

runOverlayOriginTests()
runCenteredOriginTests()
