import Foundation
import Testing
@testable import qrgo

struct SquareCaptureGeometryTests {
    private let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func `square stays centered with twice the original capture area`() {
        #expect(SquareCaptureGeometry.selectionRect(center: CGPoint(x: 720, y: 450), screenFrame: primary)
            == CGRect(x: 618, y: 348, width: 203, height: 203))
    }

    @Test func `square stays within each screen edge without changing size`() {
        let cases: [(CGPoint, CGRect)] = [
            (CGPoint(x: 0, y: 0), CGRect(x: 0, y: 0, width: 203, height: 203)),
            (CGPoint(x: 1439, y: 899), CGRect(x: 1237, y: 697, width: 203, height: 203)),
            (CGPoint(x: 0, y: 899), CGRect(x: 0, y: 697, width: 203, height: 203)),
            (CGPoint(x: 1439, y: 0), CGRect(x: 1237, y: 0, width: 203, height: 203))
        ]
        for (center, expected) in cases {
            #expect(SquareCaptureGeometry.selectionRect(center: center, screenFrame: primary) == expected)
        }
    }

    @Test func `screen coordinates handle displays left above and below the primary display`() {
        let cases: [((CGRect, CGPoint), CGRect)] = [
            ((CGRect(x: -1920, y: 0, width: 1920, height: 1080), CGPoint(x: -960, y: 540)),
             CGRect(x: -1096, y: 225, width: 271, height: 271)),
            ((CGRect(x: 0, y: 900, width: 1440, height: 900), CGPoint(x: 720, y: 1350)),
             CGRect(x: 618, y: -551, width: 203, height: 203)),
            ((CGRect(x: 0, y: -900, width: 1440, height: 900), CGPoint(x: 720, y: -450)),
             CGRect(x: 618, y: 1249, width: 203, height: 203))
        ]
        for ((screen, center), expected) in cases {
            let selection = SquareCaptureGeometry.selectionRect(center: center, screenFrame: screen)
            #expect(screen.contains(selection))
            #expect(SquareCaptureGeometry.captureRect(selection: selection, primaryScreenFrame: primary) == expected)
        }
    }

    @Test func `capture uses logical points without applying a Retina scale twice`() {
        let screen = CGRect(x: 1440, y: 0, width: 1512, height: 982)
        let selection = SquareCaptureGeometry.selectionRect(center: CGPoint(x: 2000, y: 500), screenFrame: screen)
        #expect(selection == CGRect(x: 1893, y: 393, width: 213, height: 213))
        #expect(SquareCaptureGeometry.captureRect(selection: selection, primaryScreenFrame: primary)
            == CGRect(x: 1893, y: 294, width: 213, height: 213))
    }

    @Test func `unusually short displays still contain the entire square`() {
        let screen = CGRect(x: 0, y: 0, width: 4000, height: 200)
        #expect(SquareCaptureGeometry.selectionRect(center: CGPoint(x: 2000, y: 100), screenFrame: screen)
            == CGRect(x: 1900, y: 0, width: 200, height: 200))
    }
}
