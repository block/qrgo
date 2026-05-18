import XCTest
@testable import qrgo

final class HomebrewUpdateServiceTests: XCTestCase {
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

    func testTimedOutCheckReturnsFailure() async {
        let commandRunner = FakeUpdateCommandRunner(results: [
            ShellResult(exitCode: 0, stdout: "", stderr: "", timedOut: false),
            ShellResult(exitCode: 143, stdout: "", stderr: "", timedOut: true)
        ])
        let service = HomebrewUpdateService(commandRunner: commandRunner)

        let result = await service.checkForUpdate()

        guard case .failed(let error) = result else {
            return XCTFail("Expected failed check result.")
        }
        XCTAssertTrue(error.timedOut)
    }

    func testUpdateTimeoutReturnsFailureWithoutRunningOutdatedCheck() async {
        let commandRunner = FakeUpdateCommandRunner(results: [
            ShellResult(
                exitCode: 143,
                stdout: "",
                stderr: "",
                timedOut: true
            )
        ])
        let service = HomebrewUpdateService(commandRunner: commandRunner)

        let result = await service.checkForUpdate()

        guard case .failed(let error) = result else {
            return XCTFail("Expected failed check result.")
        }
        XCTAssertEqual(error.message, "Could not update Homebrew metadata. The command timed out.")
        XCTAssertTrue(error.timedOut)
        XCTAssertEqual(commandRunner.commands.count, 1)
        XCTAssertTrue(commandRunner.commands[0].contains("brew update"))
        XCTAssertTrue(commandRunner.commands[0].contains("HOMEBREW_LOCK_CONTEXT"))
    }

    func testOutdatedCommandFailureReturnsFailureEvenWithParseableJSON() async {
        let commandRunner = FakeUpdateCommandRunner(results: [
            ShellResult(exitCode: 0, stdout: "", stderr: "", timedOut: false),
            ShellResult(
                exitCode: 1,
                stdout: #"{"formulae":[],"casks":[]}"#,
                stderr: "Homebrew failed.",
                timedOut: false
            )
        ])
        let service = HomebrewUpdateService(commandRunner: commandRunner)

        let result = await service.checkForUpdate()

        guard case .failed(let error) = result else {
            return XCTFail("Expected failed check result.")
        }
        XCTAssertEqual(error.message, "Could not check for QRGo updates.")
    }

    func testOutdatedCommandNonZeroWithQRGoCaskReturnsAvailableUpdate() async {
        let commandRunner = FakeUpdateCommandRunner(results: [
            ShellResult(exitCode: 0, stdout: "", stderr: "", timedOut: false),
            ShellResult(
                exitCode: 1,
                stdout: """
                {
                  "formulae": [],
                  "casks": [
                    {
                      "name": "qrgo-app",
                      "installed_versions": ["1.3.0"],
                      "current_version": "1.3.1"
                    }
                  ]
                }
                """,
                stderr: "",
                timedOut: false
            )
        ])
        let service = HomebrewUpdateService(commandRunner: commandRunner)

        let result = await service.checkForUpdate()

        XCTAssertEqual(result, .available(MenuBarUpdate(installedVersion: "1.3.0", currentVersion: "1.3.1")))
    }

    func testUninstalledCaskCheckReturnsUnavailable() async {
        let commandRunner = FakeUpdateCommandRunner(results: [
            ShellResult(exitCode: 0, stdout: "", stderr: "", timedOut: false),
            ShellResult(
                exitCode: 1,
                stdout: "",
                stderr: "Error: Cask 'qrgo-app' is not installed.",
                timedOut: false
            )
        ])
        let service = HomebrewUpdateService(commandRunner: commandRunner)

        let result = await service.checkForUpdate()

        XCTAssertEqual(result, .unavailable("The QRGo Homebrew cask is not installed."))
    }

    func testCheckRunsBrewUpdateWithShorterTimeoutBeforeOutdatedCheck() async {
        let commandRunner = FakeUpdateCommandRunner(results: [
            ShellResult(exitCode: 0, stdout: "", stderr: "", timedOut: false),
            ShellResult(exitCode: 0, stdout: #"{"formulae":[],"casks":[]}"#, stderr: "", timedOut: false)
        ])
        let service = HomebrewUpdateService(
            commandRunner: commandRunner,
            updateTimeout: 7,
            checkTimeout: 11
        )

        let result = await service.checkForUpdate()

        XCTAssertEqual(result, .current)
        XCTAssertEqual(commandRunner.commands.count, 2)
        XCTAssertTrue(commandRunner.commands[0].contains("brew update"))
        XCTAssertTrue(commandRunner.commands[0].contains("HOMEBREW_LOCK_CONTEXT"))
        XCTAssertTrue(commandRunner.commands[1].contains("brew outdated"))
        XCTAssertTrue(commandRunner.commands[1].contains("HOMEBREW_NO_AUTO_UPDATE=1"))
        XCTAssertEqual(commandRunner.timeouts, [7, 11])
    }

    func testInstallDetectsInteractiveHomebrewFailure() async {
        let commandRunner = FakeUpdateCommandRunner(results: [
            ShellResult(
                exitCode: 1,
                stdout: "",
                stderr: "sudo: a terminal is required to read the password",
                timedOut: false
            )
        ])
        let service = HomebrewUpdateService(commandRunner: commandRunner)

        let result = await service.installUpdate()

        guard case .failed(let error) = result else {
            return XCTFail("Expected failed install result.")
        }
        XCTAssertEqual(error.message, "Homebrew needs terminal access to finish the update.")
        XCTAssertFalse(error.details.isEmpty)
        XCTAssertTrue(commandRunner.commands[0].contains("brew upgrade"))
        XCTAssertTrue(commandRunner.commands[0].contains("HOMEBREW_NO_AUTO_UPDATE=1"))
    }

    func testInstallTimeoutUsesConciseFailureMessage() async {
        let commandRunner = FakeUpdateCommandRunner(results: [
            ShellResult(exitCode: 143, stdout: "", stderr: "", timedOut: true)
        ])
        let service = HomebrewUpdateService(commandRunner: commandRunner)

        let result = await service.installUpdate()

        guard case .failed(let error) = result else {
            return XCTFail("Expected failed install result.")
        }
        XCTAssertEqual(error.message, "The update took too long and was stopped.")
        XCTAssertTrue(error.timedOut)
    }

    func testDryRunAvailableModeReturnsAvailableUpdateAndInstallSuccess() async {
        let service = FakeUpdateService(mode: .available, checkDelay: 0, installDelay: 0)

        let checkResult = await service.checkForUpdate()
        let installResult = await service.installUpdate()

        XCTAssertEqual(checkResult, .available(MenuBarUpdate(installedVersion: "1.0.0", currentVersion: "9.9.9")))
        XCTAssertEqual(installResult, .installed)
    }

    func testDryRunCurrentModeReturnsCurrentUpdateState() async {
        let service = FakeUpdateService(mode: .current, checkDelay: 0, installDelay: 0)

        let checkResult = await service.checkForUpdate()

        XCTAssertEqual(checkResult, .current)
    }

    func testDryRunCheckErrorModeReturnsCheckFailure() async {
        let service = FakeUpdateService(mode: .checkError, checkDelay: 0, installDelay: 0)

        let checkResult = await service.checkForUpdate()

        guard case .failed(let error) = checkResult else {
            return XCTFail("Expected failed check result.")
        }
        XCTAssertEqual(error.message, "Dry-run update check failed.")
    }

    func testDryRunInstallErrorModeReturnsInstallFailure() async {
        let service = FakeUpdateService(mode: .installError, checkDelay: 0, installDelay: 0)

        let installResult = await service.installUpdate()

        guard case .failed(let error) = installResult else {
            return XCTFail("Expected failed install result.")
        }
        XCTAssertEqual(error.message, "Dry-run update install failed.")
    }

    func testInvalidDryRunModeDoesNotInvokeHomebrew() async throws {
        let service = try XCTUnwrap(FakeUpdateService.fromEnvironment([
            "QRGO_UPDATE_DRY_RUN": "typo",
            "QRGO_UPDATE_CHECK_DELAY_SECONDS": "0"
        ]))

        let checkResult = await service.checkForUpdate()

        guard case .failed(let error) = checkResult else {
            return XCTFail("Expected failed check result.")
        }
        XCTAssertEqual(error.message, "Unknown QRGo update dry-run mode.")
        XCTAssertEqual(error.details, "QRGO_UPDATE_DRY_RUN=typo")
    }
}

private final class FakeUpdateCommandRunner: MenuBarUpdateCommandRunning {
    private var results: [ShellResult]
    private(set) var commands: [String] = []
    private(set) var timeouts: [TimeInterval] = []

    init(results: [ShellResult]) {
        self.results = results
    }

    func runLoginShell(_ command: String, timeout: TimeInterval) async -> ShellResult {
        commands.append(command)
        timeouts.append(timeout)
        if results.isEmpty {
            return ShellResult(exitCode: 1, stdout: "", stderr: "No fake result.", timedOut: false)
        }
        return results.removeFirst()
    }
}
