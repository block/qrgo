import Foundation
@testable import qrgo

func makeService(
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

struct RecordedUpdateCommand: Equatable {
    let executable: String
    let arguments: [String]
    let environment: [String: String]
    let timeout: TimeInterval
    let description: String
}

final class FakeUpdateCommandRunner: MenuBarUpdateCommandRunning {
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

struct FakeHomebrewExecutableResolver: HomebrewExecutableResolving {
    var brewPath = "/opt/homebrew/bin/brew"
    var prefix: String? = "/opt/homebrew"

    func brewExecutablePath() async -> String? {
        brewPath
    }

    func homebrewPrefix(brewExecutablePath: String) async -> String? {
        prefix
    }
}

final class FakeRefreshStore: HomebrewUpdateRefreshStoring {
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

struct FakeHomebrewUpdateLockProbe: HomebrewUpdateLockProbing {
    let state: HomebrewUpdateLockState

    func updateLockState(homebrewPrefix: String) -> HomebrewUpdateLockState {
        state
    }
}

final class FakeRefreshLease: QRGoHomebrewRefreshLeasing {
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
