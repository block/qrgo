import XCTest
@testable import qrgo

final class TargetActionTests: XCTestCase {
    func testIOSActionKeyIncludesUDID() {
        XCTAssertEqual(
            TargetAction.ios(udid: "64BE9A7E-A99B-41C9-A7AF-2DA2227FF88A").key,
            "ios:64BE9A7E-A99B-41C9-A7AF-2DA2227FF88A"
        )
    }
}
