import Foundation
import Testing
@testable import qrgo

struct SquareCaptureGeometryTests {
    private let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func `square is centered and measures one tenth of screen width`() {
        #expect(SquareCaptureGeometry.selectionRect(center: CGPoint(x: 720, y: 450), screenFrame: primary)
            == CGRect(x: 648, y: 378, width: 144, height: 144))
    }

    @Test func `square stays within each screen edge without changing size`() {
        let cases: [(CGPoint, CGRect)] = [
            (CGPoint(x: 0, y: 0), CGRect(x: 0, y: 0, width: 144, height: 144)),
            (CGPoint(x: 1439, y: 899), CGRect(x: 1296, y: 756, width: 144, height: 144)),
            (CGPoint(x: 0, y: 899), CGRect(x: 0, y: 756, width: 144, height: 144)),
            (CGPoint(x: 1439, y: 0), CGRect(x: 1296, y: 0, width: 144, height: 144))
        ]
        for (center, expected) in cases {
            #expect(SquareCaptureGeometry.selectionRect(center: center, screenFrame: primary) == expected)
        }
    }

    @Test func `screen coordinates handle displays left above and below the primary display`() {
        let cases: [((CGRect, CGPoint), CGRect)] = [
            ((CGRect(x: -1920, y: 0, width: 1920, height: 1080), CGPoint(x: -960, y: 540)),
             CGRect(x: -1056, y: 264, width: 192, height: 192)),
            ((CGRect(x: 0, y: 900, width: 1440, height: 900), CGPoint(x: 720, y: 1350)),
             CGRect(x: 648, y: -522, width: 144, height: 144)),
            ((CGRect(x: 0, y: -900, width: 1440, height: 900), CGPoint(x: 720, y: -450)),
             CGRect(x: 648, y: 1278, width: 144, height: 144))
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
        #expect(selection == CGRect(x: 1924, y: 424, width: 151, height: 151))
        #expect(SquareCaptureGeometry.captureRect(selection: selection, primaryScreenFrame: primary)
            == CGRect(x: 1924, y: 325, width: 151, height: 151))
    }

    @Test func `unusually short displays still contain the entire square`() {
        let screen = CGRect(x: 0, y: 0, width: 4000, height: 200)
        #expect(SquareCaptureGeometry.selectionRect(center: CGPoint(x: 2000, y: 100), screenFrame: screen)
            == CGRect(x: 1900, y: 0, width: 200, height: 200))
    }
}
