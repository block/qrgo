import Darwin
import Foundation
import XCTest
@testable import qrgo

final class ShellTests: XCTestCase {
    func testRunCommandDoesNotTimeoutCompletedProcess() {
        let result = Shell.runCommand(
            "/bin/sh",
            arguments: ["-c", "echo done"],
            timeout: 1
        )

        XCTAssertFalse(result.timedOut)
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.trimmedOutput, "done")
    }

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

    func testRunCommandTerminatesChildProcessesOnTimeout() {
        let start = Date()

        let result = Shell.runCommand(
            "/bin/sh",
            arguments: ["-c", "sleep 5 & wait"],
            timeout: 0.1
        )

        XCTAssertTrue(result.timedOut)
        XCTAssertFalse(result.succeeded)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testRunCommandKillsChildProcessWhenRootExitsAfterTimeout() {
        let start = Date()

        let result = Shell.runCommand(
            "/bin/sh",
            arguments: ["-c", "(trap '' TERM; sleep 5) & wait"],
            timeout: 0.1
        )

        XCTAssertTrue(result.timedOut)
        XCTAssertFalse(result.succeeded)
        XCTAssertLessThan(Date().timeIntervalSince(start), 4)
    }

    func testRunCommandTimesOutWhenRootExitsButChildKeepsOutputOpen() {
        let start = Date()

        let result = Shell.runCommand(
            "/bin/sh",
            arguments: ["-c", "sleep 2 & echo $!; exit"],
            timeout: 0.1
        )

        if let childPID = pid_t(result.trimmedOutput) {
            kill(childPID, SIGKILL)
        }
        XCTAssertTrue(result.timedOut)
        XCTAssertFalse(result.succeeded)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }
}
