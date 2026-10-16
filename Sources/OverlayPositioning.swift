import CoreGraphics

enum OverlayPositioning {
    static func overlayOrigin(mouse: CGPoint, visibleFrame: CGRect, size: CGSize) -> CGPoint {
        var x = mouse.x
        var y = mouse.y - size.height

        if mouse.x + size.width > visibleFrame.maxX {
            x = mouse.x - size.width
        }
        if mouse.y - size.height < visibleFrame.minY {
            y = mouse.y
        }

        let maxX = max(visibleFrame.minX, visibleFrame.maxX - size.width)
        let maxY = max(visibleFrame.minY, visibleFrame.maxY - size.height)
        x = min(max(x, visibleFrame.minX), maxX)
        y = min(max(y, visibleFrame.minY), maxY)

        return CGPoint(x: x.rounded(), y: y.rounded())
    }

    static func centeredOrigin(visibleFrame: CGRect, size: CGSize) -> CGPoint {
        CGPoint(x: (visibleFrame.midX - size.width / 2).rounded(),
                y: (visibleFrame.midY - size.height / 2).rounded())
    }
}
