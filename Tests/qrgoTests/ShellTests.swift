import Foundation
import XCTest
@testable import qrgo

final class ShellTests: XCTestCase {
    func testRunCommandMarksTimedOutProcesses() {
        let start = Date()

        let result = Shell.runCommand(
            "/bin/sh",
            arguments: ["-c", "sleep 5"],
            timeout: 0.1
        )

        XCTAssertTrue(result.timedOut)
        XCTAssertFalse(result.succeeded)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }
}
