import XCTest
@testable import qrgo

final class HomebrewUpdateParsingTests: XCTestCase {
    func testOutdatedJSONWithNoCasksReturnsCurrent() throws {
        let result = try HomebrewUpdateService.checkResult(fromOutdatedJSON: """
        {
          "formulae": [],
          "casks": []
        }
        """)

        XCTAssertEqual(result, .current)
    }

    func testOutdatedJSONWithQRGoCaskReturnsAvailableUpdate() throws {
        let result = try HomebrewUpdateService.checkResult(fromOutdatedJSON: """
        {
          "formulae": [],
          "casks": [
            {
              "name": "qrgo-app",
              "installed_versions": ["1.2.0"],
              "current_version": "1.3.0"
            }
          ]
        }
        """)

        XCTAssertEqual(result, .available(MenuBarUpdate(installedVersion: "1.2.0", currentVersion: "1.3.0")))
    }

    func testOutdatedJSONWithUnrelatedCaskReturnsCurrent() throws {
        let result = try HomebrewUpdateService.checkResult(fromOutdatedJSON: """
        {
          "formulae": [],
          "casks": [
            {
              "name": "other-app",
              "installed_versions": ["1.0.0"],
              "current_version": "2.0.0"
            }
          ]
        }
        """)

        XCTAssertEqual(result, .current)
    }

    func testMalformedOutdatedJSONThrows() {
        XCTAssertThrowsError(try HomebrewUpdateService.checkResult(fromOutdatedJSON: "{"))
    }
}
