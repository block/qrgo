import XCTest
@testable import qrgo

final class HomebrewUpdateServiceTests: XCTestCase {
    func testPassiveModeRunsOnlyOutdatedCheck() async {
        let commandRunner = FakeUpdateCommandRunner(results: [
            ShellResult(exitCode: 0, stdout: #"{"formulae":[],"casks":[]}"#, stderr: "", timedOut: false)
        ])
        var logs: [String] = []
        let service = makeService(commandRunner: commandRunner, log: { logs.append($0) })

        let result = await service.checkForUpdate(mode: .passive)

        XCTAssertEqual(result, .current)
        XCTAssertEqual(commandRunner.commands.map(\.arguments), [
            ["outdated", "--cask", "--json=v2", "block/tap/qrgo-app"]
        ])
        XCTAssertEqual(commandRunner.commands[0].environment["HOMEBREW_NO_AUTO_UPDATE"], "1")
        XCTAssertTrue(logs.contains("Checking QRGo Homebrew update state in passive mode."))
        XCTAssertTrue(logs.contains(
            "Starting QRGo Homebrew command: brew outdated --cask --json=v2 block/tap/qrgo-app."
        ))
        XCTAssertTrue(logs.contains(
            "Finished QRGo Homebrew command: brew outdated --cask --json=v2 block/tap/qrgo-app with exit code 0."
        ))
    }

    func testRefreshModeWithRecentAttemptRunsOnlyOutdatedCheck() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = FakeRefreshStore(lastRefreshAttemptAt: now.addingTimeInterval(-60))
        let commandRunner = FakeUpdateCommandRunner(results: [
            ShellResult(exitCode: 0, stdout: #"{"formulae":[],"casks":[]}"#, stderr: "", timedOut: false)
        ])
        let service = makeService(
            commandRunner: commandRunner,
            refreshStore: store,
            dateProvider: { now }
        )

        let result = await service.checkForUpdate(mode: .refreshIfDue)

        XCTAssertEqual(result, .current)
        XCTAssertEqual(commandRunner.commands.map(\.arguments), [
            ["outdated", "--cask", "--json=v2", "block/tap/qrgo-app"]
        ])
    }

    func testRefreshAttemptRecordsBeforePrefixResolution() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = FakeRefreshStore()
        let service = makeService(
            commandRunner: FakeUpdateCommandRunner(results: []),
            executableResolver: FakeHomebrewExecutableResolver(prefix: nil),
            refreshStore: store,
            dateProvider: { now }
        )

        let result = await service.checkForUpdate(mode: .refreshIfDue)

        XCTAssertEqual(result, .unavailable("Homebrew is not available."))
        XCTAssertEqual(store.lastRefreshAttemptAt, now)
        XCTAssertEqual(store.firstRefreshAttemptWithoutSuccessAt, now)
        XCTAssertEqual(store.lastRefreshFailureReason, "Homebrew is not available.")
    }

    func testStaleMetadataLogUsesFirstAttemptWithoutSuccess() async {
        let now = Date(timeIntervalSince1970: 8 * 24 * 60 * 60)
        let store = FakeRefreshStore(
            lastRefreshAttemptAt: now.addingTimeInterval(-60),
            firstRefreshAttemptWithoutSuccessAt: Date(timeIntervalSince1970: 0)
        )
        let commandRunner = FakeUpdateCommandRunner(results: [
            ShellResult(exitCode: 0, stdout: #"{"formulae":[],"casks":[]}"#, stderr: "", timedOut: false)
        ])
        var logs: [String] = []
        let service = makeService(
            commandRunner: commandRunner,
            refreshStore: store,
            dateProvider: { now },
            log: { logs.append($0) }
        )

        _ = await service.checkForUpdate(mode: .refreshIfDue)

        XCTAssertTrue(logs.contains("QRGo Homebrew metadata has not refreshed successfully for 8 day(s)."))
        XCTAssertEqual(commandRunner.commands.map(\.arguments), [
            ["outdated", "--cask", "--json=v2", "block/tap/qrgo-app"]
        ])
    }

    func testStaleMetadataLogRunsWhenRefreshIsUnavailable() async {
        let now = Date(timeIntervalSince1970: 8 * 24 * 60 * 60)
        let store = FakeRefreshStore(firstRefreshAttemptWithoutSuccessAt: Date(timeIntervalSince1970: 0))
        let commandRunner = FakeUpdateCommandRunner(results: [])
        var logs: [String] = []
        let service = makeService(
            commandRunner: commandRunner,
            refreshStore: store,
            lockProbe: FakeHomebrewUpdateLockProbe(state: .held("brew pid 123")),
            dateProvider: { now },
            log: { logs.append($0) }
        )

        _ = await service.checkForUpdate(mode: .refreshIfDue)

        XCTAssertTrue(logs.contains("QRGo Homebrew metadata has not refreshed successfully for 8 day(s)."))
        XCTAssertTrue(commandRunner.commands.isEmpty)
    }
}

final class HomebrewMetadataRefreshExecutionTests: XCTestCase {
    func testDueRefreshRunsUpdateIfNeededBeforeOutdatedCheck() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = FakeRefreshStore()
        let commandRunner = FakeUpdateCommandRunner(results: [
            ShellResult(exitCode: 0, stdout: "", stderr: "", timedOut: false),
            ShellResult(exitCode: 0, stdout: #"{"formulae":[],"casks":[]}"#, stderr: "", timedOut: false)
        ])
        var logs: [String] = []
        let service = makeService(
            commandRunner: commandRunner,
            refreshStore: store,
            dateProvider: { now },
            log: { logs.append($0) }
        )

        let result = await service.checkForUpdate(mode: .refreshIfDue)

        XCTAssertEqual(result, .current)
        XCTAssertEqual(commandRunner.commands.map(\.arguments), [
            ["update-if-needed"],
            ["outdated", "--cask", "--json=v2", "block/tap/qrgo-app"]
        ])
        XCTAssertEqual(
            commandRunner.commands[0].environment["HOMEBREW_LOCK_CONTEXT"],
            "QRGo is checking for updates in the background."
        )
        XCTAssertEqual(commandRunner.commands[0].environment["HOMEBREW_NO_ENV_HINTS"], "1")
        XCTAssertEqual(store.lastRefreshAttemptAt, now)
        XCTAssertEqual(store.lastRefreshSucceededAt, now)
        XCTAssertNil(store.lastRefreshFailureReason)
        XCTAssertNil(store.firstRefreshAttemptWithoutSuccessAt)
        XCTAssertTrue(logs.contains("Checking QRGo Homebrew update state in refreshIfDue mode."))
        XCTAssertTrue(logs.contains("Starting QRGo Homebrew command: brew update-if-needed."))
        XCTAssertTrue(logs.contains("Finished QRGo Homebrew command: brew update-if-needed with exit code 0."))
        XCTAssertTrue(logs.contains(
            "Starting QRGo Homebrew command: brew outdated --cask --json=v2 block/tap/qrgo-app."
        ))
        XCTAssertTrue(logs.contains(
            "Finished QRGo Homebrew command: brew outdated --cask --json=v2 block/tap/qrgo-app with exit code 0."
        ))
    }

    func testHomebrewOptOutForcesPassiveOnlyBehavior() async {
        let commandRunner = FakeUpdateCommandRunner(results: [
            ShellResult(exitCode: 0, stdout: #"{"formulae":[],"casks":[]}"#, stderr: "", timedOut: false)
        ])
        let service = makeService(
            commandRunner: commandRunner,
            environment: ["HOMEBREW_NO_AUTO_UPDATE": "1"]
        )

        let result = await service.checkForUpdate(mode: .refreshIfDue)

        XCTAssertEqual(result, .current)
        XCTAssertEqual(commandRunner.commands.map(\.arguments), [
            ["outdated", "--cask", "--json=v2", "block/tap/qrgo-app"]
        ])
    }

    func testQRGoRefreshOptOutForcesPassiveOnlyBehavior() async {
        let commandRunner = FakeUpdateCommandRunner(results: [
            ShellResult(exitCode: 0, stdout: #"{"formulae":[],"casks":[]}"#, stderr: "", timedOut: false)
        ])
        let service = makeService(
            commandRunner: commandRunner,
            environment: ["QRGO_DISABLE_BACKGROUND_HOMEBREW_REFRESH": "1"]
        )

        let result = await service.checkForUpdate(mode: .refreshIfDue)

        XCTAssertEqual(result, .current)
        XCTAssertEqual(commandRunner.commands.map(\.arguments), [
            ["outdated", "--cask", "--json=v2", "block/tap/qrgo-app"]
        ])
    }

    func testHeldUpdateLockSkipsRefreshAndOutdatedCheck() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = FakeRefreshStore()
        let commandRunner = FakeUpdateCommandRunner(results: [])
        let service = makeService(
            commandRunner: commandRunner,
            refreshStore: store,
            lockProbe: FakeHomebrewUpdateLockProbe(state: .held("brew pid 123")),
            dateProvider: { now }
        )

        let result = await service.checkForUpdate(mode: .refreshIfDue)

        XCTAssertEqual(result, .unavailable("Another Homebrew update is already running."))
        XCTAssertTrue(commandRunner.commands.isEmpty)
        XCTAssertEqual(store.lastRefreshAttemptAt, now)
        XCTAssertEqual(store.lastRefreshFailureReason, "Homebrew update lock is held.")
        XCTAssertEqual(store.firstRefreshAttemptWithoutSuccessAt, now)
    }

    func testUnprobeableUpdateLockSkipsRefreshAndOutdatedCheck() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = FakeRefreshStore()
        let commandRunner = FakeUpdateCommandRunner(results: [])
        let service = makeService(
            commandRunner: commandRunner,
            refreshStore: store,
            lockProbe: FakeHomebrewUpdateLockProbe(state: .unavailable("Probe failed.")),
            dateProvider: { now }
        )

        let result = await service.checkForUpdate(mode: .refreshIfDue)

        XCTAssertEqual(result, .unavailable("Another Homebrew update is already running."))
        XCTAssertTrue(commandRunner.commands.isEmpty)
        XCTAssertEqual(store.lastRefreshAttemptAt, now)
        XCTAssertEqual(store.lastRefreshFailureReason, "Probe failed.")
        XCTAssertEqual(store.firstRefreshAttemptWithoutSuccessAt, now)
    }

    func testQRGoLeaseContentionSkipsRefreshAndOutdatedCheck() async {
        let store = FakeRefreshStore()
        let commandRunner = FakeUpdateCommandRunner(results: [])
        let service = makeService(
            commandRunner: commandRunner,
            refreshStore: store,
            refreshLease: FakeRefreshLease(result: .unavailable("Already running."))
        )

        let result = await service.checkForUpdate(mode: .refreshIfDue)

        XCTAssertEqual(result, .unavailable("QRGo is already checking for Homebrew updates."))
        XCTAssertTrue(commandRunner.commands.isEmpty)
        XCTAssertEqual(store.lastRefreshFailureReason, "Already running.")
    }

    func testLockRaceOutputReturnsUnavailable() async {
        let store = FakeRefreshStore()
        let commandRunner = FakeUpdateCommandRunner(results: [
            ShellResult(
                exitCode: 1,
                stdout: "",
                stderr: "lockf: 200: already locked\nError: Another `brew update` process is already running.",
                timedOut: false
            )
        ])
        let service = makeService(commandRunner: commandRunner, refreshStore: store)

        let result = await service.checkForUpdate(mode: .refreshIfDue)

        XCTAssertEqual(result, .unavailable("Another Homebrew update is already running."))
        XCTAssertEqual(commandRunner.commands.map(\.arguments), [["update-if-needed"]])
        XCTAssertEqual(store.lastRefreshFailureReason, "Homebrew update lock is held.")
    }

    func testUpdateIfNeededUnavailableFallsBackToBrewUpdate() async {
        let commandRunner = FakeUpdateCommandRunner(results: [
            ShellResult(exitCode: 1, stdout: "", stderr: "Error: Unknown command: update-if-needed", timedOut: false),
            ShellResult(exitCode: 0, stdout: "", stderr: "", timedOut: false),
            ShellResult(exitCode: 0, stdout: #"{"formulae":[],"casks":[]}"#, stderr: "", timedOut: false)
        ])
        let service = makeService(commandRunner: commandRunner)

        let result = await service.checkForUpdate(mode: .refreshIfDue)

        XCTAssertEqual(result, .current)
        XCTAssertEqual(commandRunner.commands.map(\.arguments), [
            ["update-if-needed"],
            ["update", "--auto-update", "--quiet"],
            ["outdated", "--cask", "--json=v2", "block/tap/qrgo-app"]
        ])
    }

    func testRefreshTimeoutRecordsFailureAndContinuesWithOutdatedCheck() async {
        let store = FakeRefreshStore()
        let commandRunner = FakeUpdateCommandRunner(results: [
            ShellResult(exitCode: 143, stdout: "", stderr: "", timedOut: true),
            ShellResult(exitCode: 0, stdout: #"{"formulae":[],"casks":[]}"#, stderr: "", timedOut: false)
        ])
        let service = makeService(commandRunner: commandRunner, refreshStore: store)

        let result = await service.checkForUpdate(mode: .refreshIfDue)

        XCTAssertEqual(result, .current)
        XCTAssertEqual(commandRunner.commands.map(\.arguments), [
            ["update-if-needed"],
            ["outdated", "--cask", "--json=v2", "block/tap/qrgo-app"]
        ])
        XCTAssertEqual(store.lastRefreshFailureReason, "Could not update Homebrew metadata. The command timed out.")
        XCTAssertEqual(store.firstRefreshAttemptWithoutSuccessAt, Date(timeIntervalSince1970: 1_000))
    }

    func testRefreshFailureRecordsFailureAndContinuesWithOutdatedCheck() async {
        let firstAttemptWithoutSuccess = Date(timeIntervalSince1970: 900)
        let store = FakeRefreshStore(firstRefreshAttemptWithoutSuccessAt: firstAttemptWithoutSuccess)
        let commandRunner = FakeUpdateCommandRunner(results: [
            ShellResult(exitCode: 1, stdout: "", stderr: "network failed", timedOut: false),
            ShellResult(exitCode: 0, stdout: #"{"formulae":[],"casks":[]}"#, stderr: "", timedOut: false)
        ])
        let service = makeService(commandRunner: commandRunner, refreshStore: store)

        let result = await service.checkForUpdate(mode: .refreshIfDue)

        XCTAssertEqual(result, .current)
        XCTAssertEqual(commandRunner.commands.map(\.arguments), [
            ["update-if-needed"],
            ["outdated", "--cask", "--json=v2", "block/tap/qrgo-app"]
        ])
        XCTAssertEqual(store.lastRefreshFailureReason, "Could not update Homebrew metadata.")
        XCTAssertEqual(store.firstRefreshAttemptWithoutSuccessAt, firstAttemptWithoutSuccess)
    }

    func testRefreshCancellationReturnsFailureWithoutRunningOutdatedCheck() async {
        let store = FakeRefreshStore()
        let commandRunner = FakeUpdateCommandRunner(results: [
            ShellResult(exitCode: 143, stdout: "", stderr: "", timedOut: false, cancelled: true)
        ])
        let service = makeService(commandRunner: commandRunner, refreshStore: store)

        let result = await service.checkForUpdate(mode: .refreshIfDue)

        guard case .failed(let error) = result else {
            return XCTFail("Expected failure.")
        }
        XCTAssertEqual(error.message, "Could not update Homebrew metadata. The command was cancelled.")
        XCTAssertFalse(error.timedOut)
        XCTAssertEqual(commandRunner.commands.map(\.arguments), [["update-if-needed"]])
        XCTAssertEqual(store.lastRefreshFailureReason, "Could not update Homebrew metadata. The command was cancelled.")
        XCTAssertEqual(store.firstRefreshAttemptWithoutSuccessAt, Date(timeIntervalSince1970: 1_000))
    }
}

final class HomebrewOutdatedCheckTests: XCTestCase {
    func testOutdatedCommandFailureReturnsFailureEvenWithParseableJSON() async {
        let commandRunner = FakeUpdateCommandRunner(results: [
            ShellResult(
                exitCode: 1,
                stdout: #"{"formulae":[],"casks":[]}"#,
                stderr: "Homebrew failed.",
                timedOut: false
            )
        ])
        let service = makeService(commandRunner: commandRunner)

        let result = await service.checkForUpdate(mode: .passive)

        guard case .failed(let error) = result else {
            return XCTFail("Expected failed check result.")
        }
        XCTAssertEqual(error.message, "Could not check for QRGo updates.")
    }

    func testOutdatedCommandNonZeroWithQRGoCaskReturnsAvailableUpdate() async {
        let commandRunner = FakeUpdateCommandRunner(results: [
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
        let service = makeService(commandRunner: commandRunner)

        let result = await service.checkForUpdate(mode: .passive)

        XCTAssertEqual(result, .available(MenuBarUpdate(installedVersion: "1.3.0", currentVersion: "1.3.1")))
    }

    func testUninstalledCaskCheckReturnsUnavailable() async {
        let commandRunner = FakeUpdateCommandRunner(results: [
            ShellResult(
                exitCode: 1,
                stdout: "",
                stderr: "Error: Cask 'qrgo-app' is not installed.",
                timedOut: false
            )
        ])
        let service = makeService(commandRunner: commandRunner)

        let result = await service.checkForUpdate(mode: .passive)

        XCTAssertEqual(result, .unavailable("The QRGo Homebrew cask is not installed."))
    }

    func testOutdatedLockRaceOutputReturnsUnavailable() async {
        let commandRunner = FakeUpdateCommandRunner(results: [
            ShellResult(
                exitCode: 1,
                stdout: "",
                stderr: "lockf: 200: already locked\nError: Another `brew update` process is already running.",
                timedOut: false
            )
        ])
        let service = makeService(commandRunner: commandRunner)

        let result = await service.checkForUpdate(mode: .passive)

        XCTAssertEqual(result, .unavailable("Another Homebrew update is already running."))
    }
}

final class HomebrewUpdateInstallTests: XCTestCase {
    func testInstallUsesNoAutoUpdateNoHintsAndNoCleanup() async {
        let commandRunner = FakeUpdateCommandRunner(results: [
            ShellResult(exitCode: 0, stdout: "", stderr: "", timedOut: false)
        ])
        let service = makeService(commandRunner: commandRunner)

        let result = await service.installUpdate()

        XCTAssertEqual(result, .installed)
        XCTAssertEqual(commandRunner.commands.map(\.arguments), [
            ["upgrade", "--cask", "block/tap/qrgo-app"]
        ])
        XCTAssertEqual(commandRunner.commands[0].environment["HOMEBREW_NO_AUTO_UPDATE"], "1")
        XCTAssertEqual(commandRunner.commands[0].environment["HOMEBREW_NO_ENV_HINTS"], "1")
        XCTAssertEqual(commandRunner.commands[0].environment["HOMEBREW_NO_INSTALL_CLEANUP"], "1")
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
        let service = makeService(commandRunner: commandRunner)

        let result = await service.installUpdate()

        guard case .failed(let error) = result else {
            return XCTFail("Expected failed install result.")
        }
        XCTAssertEqual(error.message, "Homebrew needs terminal access to finish the update.")
        XCTAssertFalse(error.details.isEmpty)
    }

    func testInstallTimeoutUsesConciseFailureMessage() async {
        let commandRunner = FakeUpdateCommandRunner(results: [
            ShellResult(exitCode: 143, stdout: "", stderr: "", timedOut: true)
        ])
        let service = makeService(commandRunner: commandRunner)

        let result = await service.installUpdate()

        guard case .failed(let error) = result else {
            return XCTFail("Expected failed install result.")
        }
        XCTAssertEqual(error.message, "The update took too long and was stopped.")
        XCTAssertTrue(error.timedOut)
    }
}

private func makeService(
    commandRunner: FakeUpdateCommandRunner,
    executableResolver: HomebrewExecutableResolving = FakeHomebrewExecutableResolver(),
    refreshStore: FakeRefreshStore = FakeRefreshStore(),
    lockProbe: HomebrewUpdateLockProbing = FakeHomebrewUpdateLockProbe(state: .unlocked),
    refreshLease: QRGoHomebrewRefreshLeasing = FakeRefreshLease(),
    environment: [String: String] = [:],
    dateProvider: @escaping () -> Date = { Date(timeIntervalSince1970: 1_000) },
    log: @escaping (String) -> Void = { _ in },
    logError: @escaping (String) -> Void = { _ in }
) -> HomebrewUpdateService {
    HomebrewUpdateService(
        commandRunner: commandRunner,
        executableResolver: executableResolver,
        refreshStore: refreshStore,
        lockProbe: lockProbe,
        refreshLease: refreshLease,
        environment: environment,
        dateProvider: dateProvider,
        refreshInterval: 24 * 60 * 60,
        staleMetadataInterval: 7 * 24 * 60 * 60,
        refreshTimeout: 7,
        checkTimeout: 11,
        installTimeout: 13,
        log: log,
        logError: logError
    )
}

private struct RecordedUpdateCommand: Equatable {
    let executable: String
    let arguments: [String]
    let environment: [String: String]
    let timeout: TimeInterval
    let description: String
}

private final class FakeUpdateCommandRunner: MenuBarUpdateCommandRunning {
    private var results: [ShellResult]
    private(set) var commands: [RecordedUpdateCommand] = []

    init(results: [ShellResult]) {
        self.results = results
    }

    func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval,
        description: String
    ) async -> ShellResult {
        commands.append(RecordedUpdateCommand(
            executable: executable,
            arguments: arguments,
            environment: environment,
            timeout: timeout,
            description: description
        ))
        if results.isEmpty {
            return ShellResult(exitCode: 1, stdout: "", stderr: "No fake result.", timedOut: false)
        }
        return results.removeFirst()
    }
}

private struct FakeHomebrewExecutableResolver: HomebrewExecutableResolving {
    var brewPath = "/opt/homebrew/bin/brew"
    var prefix: String? = "/opt/homebrew"

    func brewExecutablePath() async -> String? {
        brewPath
    }

    func homebrewPrefix(brewExecutablePath: String) async -> String? {
        prefix
    }
}

private final class FakeRefreshStore: HomebrewUpdateRefreshStoring {
    var lastRefreshAttemptAt: Date?
    var lastRefreshSucceededAt: Date?
    var lastRefreshFailureReason: String?
    var firstRefreshAttemptWithoutSuccessAt: Date?

    init(
        lastRefreshAttemptAt: Date? = nil,
        lastRefreshSucceededAt: Date? = nil,
        lastRefreshFailureReason: String? = nil,
        firstRefreshAttemptWithoutSuccessAt: Date? = nil
    ) {
        self.lastRefreshAttemptAt = lastRefreshAttemptAt
        self.lastRefreshSucceededAt = lastRefreshSucceededAt
        self.lastRefreshFailureReason = lastRefreshFailureReason
        self.firstRefreshAttemptWithoutSuccessAt = firstRefreshAttemptWithoutSuccessAt
    }
}

private struct FakeHomebrewUpdateLockProbe: HomebrewUpdateLockProbing {
    let state: HomebrewUpdateLockState

    func updateLockState(homebrewPrefix: String) -> HomebrewUpdateLockState {
        state
    }
}

private final class FakeRefreshLease: QRGoHomebrewRefreshLeasing {
    private let result: QRGoHomebrewRefreshLeaseResult
    private(set) var releasedLeases: [QRGoHomebrewRefreshLease] = []

    init(result: QRGoHomebrewRefreshLeaseResult = .acquired(QRGoHomebrewRefreshLease(id: "lease"))) {
        self.result = result
    }

    func acquire(mode: String, now: Date) -> QRGoHomebrewRefreshLeaseResult {
        result
    }

    func release(_ lease: QRGoHomebrewRefreshLease) {
        releasedLeases.append(lease)
    }
}
