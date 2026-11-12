import AppKit
import Testing
@testable import qrgo

@MainActor
struct SquareCapturePanelTests {
    @Test func `overlay paints click receiving pixels across the entire capture surface`() throws {
        _ = NSApplication.shared
        let panel = SquareCapturePanel(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        let view = try #require(panel.contentView as? SquareCaptureView)
        view.selectionRect = CGRect(x: 100, y: 50, width: 200, height: 200)
        let image = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: image)

        // Sample both the center and screen edges. Fully clear pixels can pass clicks to other apps.
        for (xFraction, yFraction) in [(0.0, 0.0), (0.5, 0.5), (0.99, 0.99)] {
            let color = try #require(image.colorAt(
                x: Int(Double(image.pixelsWide - 1) * xFraction),
                y: Int(Double(image.pixelsHigh - 1) * yFraction)
            ))
            #expect(color.alphaComponent > 0)
            #expect(color.alphaComponent < 0.1)
            if xFraction == 0.5 {
                #expect(color.alphaComponent < 0.01)
            } else {
                #expect(color.alphaComponent > 0.05)
            }
        }
        #expect(view.acceptsFirstMouse(for: nil))
        #expect(!panel.ignoresMouseEvents)
    }
}
