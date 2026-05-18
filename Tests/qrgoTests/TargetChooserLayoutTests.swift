import XCTest
@testable import qrgo

final class TargetChooserLayoutTests: XCTestCase {
    func testContentSizeHandlesEmptyOptionListWithoutPhantomViewport() {
        let layout = TargetChooserLayout(optionCount: 0, hasFooter: false)

        XCTAssertEqual(layout.buttonStackHeight, 0)
        XCTAssertEqual(layout.buttonViewportHeight, 0)
        XCTAssertFalse(layout.requiresScrolling)
    }

    func testContentSizeFitsSmallOptionListWithoutScrolling() {
        let layout = TargetChooserLayout(optionCount: 4, hasFooter: false)

        XCTAssertEqual(layout.contentSize.width, TargetChooserLayout.width)
        XCTAssertLessThan(layout.contentSize.height, TargetChooserLayout.maxHeight)
        XCTAssertEqual(layout.buttonViewportHeight, layout.buttonStackHeight)
        XCTAssertFalse(layout.requiresScrolling)
    }

    func testContentSizeIncludesFooterWithoutScrollingWhenUnderMaxHeight() {
        let layout = TargetChooserLayout(optionCount: 5, hasFooter: true)

        XCTAssertEqual(layout.contentSize.width, TargetChooserLayout.width)
        XCTAssertLessThan(layout.contentSize.height, TargetChooserLayout.maxHeight)
        XCTAssertEqual(layout.buttonViewportHeight, layout.buttonStackHeight)
        XCTAssertFalse(layout.requiresScrolling)
    }

    func testContentSizeCapsLargeOptionListAndScrollsButtons() {
        let layout = TargetChooserLayout(optionCount: 20, hasFooter: true)

        XCTAssertEqual(layout.contentSize.width, TargetChooserLayout.width)
        XCTAssertEqual(layout.contentSize.height, TargetChooserLayout.maxHeight)
        XCTAssertLessThan(layout.buttonViewportHeight, layout.buttonStackHeight)
        XCTAssertTrue(layout.requiresScrolling)
    }

    func testContentSizeKeepsUrlAreaBounded() {
        let layout = TargetChooserLayout(optionCount: 5, hasFooter: false)

        XCTAssertEqual(TargetChooserLayout.urlHeight, 48)
        XCTAssertLessThan(
            TargetChooserLayout.urlHeight,
            layout.contentSize.height - layout.buttonViewportHeight
        )
    }
}
