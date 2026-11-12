import Foundation

enum SquareCaptureGeometry {
    /// Logical points keep the outline and capture region aligned on Retina displays.
    static func selectionRect(center: CGPoint, screenFrame: CGRect) -> CGRect {
        let side = min(max(1, floor(screenFrame.width * sqrt(2) / 10)), screenFrame.width, screenFrame.height)
        let origin = CGPoint(
            x: min(max(floor(center.x - side / 2), screenFrame.minX), screenFrame.maxX - side),
            y: min(max(floor(center.y - side / 2), screenFrame.minY), screenFrame.maxY - side)
        )
        return CGRect(origin: origin, size: CGSize(width: side, height: side))
    }

    /// AppKit uses a bottom-left origin; screencapture uses the primary display's top-left origin.
    static func captureRect(selection: CGRect, primaryScreenFrame: CGRect) -> CGRect {
        CGRect(
            x: selection.minX - primaryScreenFrame.minX,
            y: primaryScreenFrame.maxY - selection.maxY,
            width: selection.width,
            height: selection.height
        )
    }
}
