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

    func testIsolatedRunnerPreservesOutputAndEnvironment() async {
        let runner = IsolatedProcessRunner(terminationDelay: 0.1)

        let result = await runner.run(
            executable: "/bin/sh",
            arguments: ["-c", "printf \"$QRGO_TEST_VALUE\"; printf err >&2"],
            environment: ["QRGO_TEST_VALUE": "ok"],
            timeout: 2,
            description: "test output"
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.stdout, "ok")
        XCTAssertEqual(result.stderr, "err")
    }

    func testIsolatedRunnerPreservesNonZeroExitCode() async {
        let runner = IsolatedProcessRunner(terminationDelay: 0.1)

        let result = await runner.run(
            executable: "/bin/sh",
            arguments: ["-c", "printf out; printf err >&2; exit 42"],
            environment: [:],
            timeout: 2,
            description: "test nonzero exit"
        )

        XCTAssertEqual(result.exitCode, 42)
        XCTAssertFalse(result.succeeded)
        XCTAssertFalse(result.timedOut)
        XCTAssertFalse(result.cancelled)
        XCTAssertEqual(result.stdout, "out")
        XCTAssertEqual(result.stderr, "err")
    }

    func testIsolatedRunnerKillsChildProcessOnTimeout() async {
        let start = Date()
        let childPIDURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        defer {
            try? FileManager.default.removeItem(at: childPIDURL)
        }
        let runner = IsolatedProcessRunner(terminationDelay: 0.1)

        let result = await runner.run(
            executable: "/bin/sh",
            arguments: ["-c", "(trap '' TERM; sleep 5) & echo $! > \"$QRGO_CHILD_PID_FILE\"; wait"],
            environment: ["QRGO_CHILD_PID_FILE": childPIDURL.path],
            timeout: 0.1,
            description: "test timeout"
        )

        XCTAssertTrue(result.timedOut)
        XCTAssertFalse(result.succeeded)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        guard let childPID = pidFromFile(at: childPIDURL) else {
            return XCTFail("Expected timeout test child PID.")
        }
        let childExited = await waitUntilProcessExits(childPID, timeout: 2)
        XCTAssertTrue(childExited)
    }

    func testIsolatedRunnerCleansUpChildWhenRootExits() async {
        let start = Date()
        let childPIDURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        defer {
            try? FileManager.default.removeItem(at: childPIDURL)
        }
        let runner = IsolatedProcessRunner(terminationDelay: 0.1)

        let result = await runner.run(
            executable: "/bin/sh",
            arguments: ["-c", "sleep 5 & echo $! > \"$QRGO_CHILD_PID_FILE\"; echo child-started; exit"],
            environment: ["QRGO_CHILD_PID_FILE": childPIDURL.path],
            timeout: 2,
            description: "test root exit"
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.trimmedOutput, "child-started")
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
        guard let childPID = pidFromFile(at: childPIDURL) else {
            return XCTFail("Expected root-exit test child PID.")
        }
        let childExited = await waitUntilProcessExits(childPID, timeout: 2)
        XCTAssertTrue(childExited)
    }

    func testIsolatedRunnerKillsProcessGroupOnCancellation() async {
        let childPIDURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        defer {
            try? FileManager.default.removeItem(at: childPIDURL)
        }
        let runner = IsolatedProcessRunner(terminationDelay: 0.1)
        let task = Task {
            await runner.run(
                executable: "/bin/sh",
                arguments: ["-c", "(trap '' TERM; sleep 5) & echo $! > \"$QRGO_CHILD_PID_FILE\"; wait"],
                environment: ["QRGO_CHILD_PID_FILE": childPIDURL.path],
                timeout: 5,
                description: "test cancellation"
            )
        }

        try? await Task.sleep(nanoseconds: 100_000_000)
        guard let childPID = pidFromFile(at: childPIDURL) else {
            task.cancel()
            _ = await task.value
            return XCTFail("Expected cancellation test child PID.")
        }
        task.cancel()
        let result = await task.value

        XCTAssertTrue(result.cancelled)
        XCTAssertFalse(result.succeeded)
        let childExited = await waitUntilProcessExits(childPID, timeout: 2)
        XCTAssertTrue(childExited)
    }

    func testIsolatedRunnerDoesNotSpawnWhenAlreadyCancelled() async {
        let markerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        defer {
            try? FileManager.default.removeItem(at: markerURL)
        }
        let runner = IsolatedProcessRunner(terminationDelay: 0.1)
        let task = Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            return await runner.run(
                executable: "/bin/sh",
                arguments: ["-c", "echo spawned > \"$QRGO_MARKER_FILE\""],
                environment: ["QRGO_MARKER_FILE": markerURL.path],
                timeout: 2,
                description: "test pre-cancelled runner"
            )
        }

        task.cancel()
        let result = await task.value

        XCTAssertTrue(result.cancelled)
        XCTAssertFalse(result.succeeded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
    }
}

private func pidFromFile(at url: URL) -> pid_t? {
    guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
        return nil
    }
    return pid_t(contents.trimmingCharacters(in: .whitespacesAndNewlines))
}

private func waitUntilProcessExits(_ processID: pid_t, timeout: TimeInterval) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if !processExists(processID) {
            return true
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return !processExists(processID)
}

private func processExists(_ processID: pid_t) -> Bool {
    if kill(processID, 0) == 0 {
        return true
    }
    return errno == EPERM
}
