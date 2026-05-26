import Foundation

/// Version pair reported by Homebrew when the QRGo cask is outdated.
struct MenuBarUpdate: Equatable {
    let installedVersion: String
    let currentVersion: String
}

enum MenuBarUpdateCheckMode: Equatable {
    case passive
    case refreshIfDue
}

/// Result of a background menu bar update check.
enum MenuBarUpdateCheckResult: Equatable {
    case current
    case available(MenuBarUpdate)
    case unavailable(String)
    case failed(MenuBarUpdateCommandError)
}

private extension MenuBarUpdateCheckResult {
    var hasAvailableUpdate: Bool {
        guard case .available = self else {
            return false
        }
        return true
    }
}

/// Result of a user-initiated Homebrew cask upgrade.
enum MenuBarUpdateInstallResult: Equatable {
    case installed
    case failed(MenuBarUpdateCommandError)
}

/// Command failure details used for user-facing errors and full diagnostic logs.
struct MenuBarUpdateCommandError: Error, Equatable {
    let message: String
    let details: String
    let timedOut: Bool
}

/// Checks for and installs QRGo updates without tying callers to Homebrew or dry-run behavior.
protocol MenuBarUpdateServicing {
    var mayUnloadLaunchAgentDuringInstall: Bool { get }

    func checkForUpdate(mode: MenuBarUpdateCheckMode) async -> MenuBarUpdateCheckResult
    func installUpdate() async -> MenuBarUpdateInstallResult
}

extension MenuBarUpdateServicing {
    var mayUnloadLaunchAgentDuringInstall: Bool { false }
}

protocol MenuBarUpdateCommandRunning {
    func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval,
        description: String
    ) async -> ShellResult
}

struct IsolatedMenuBarUpdateCommandRunner: MenuBarUpdateCommandRunning {
    private let runner: IsolatedProcessRunning

    init(runner: IsolatedProcessRunning = IsolatedProcessRunner()) {
        self.runner = runner
    }

    func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval,
        description: String
    ) async -> ShellResult {
        await runner.run(
            executable: executable,
            arguments: arguments,
            environment: environment,
            timeout: timeout,
            description: description
        )
    }
}

/// Production update service backed by the `block/tap/qrgo-app` Homebrew cask.
struct HomebrewUpdateService: MenuBarUpdateServicing {
    static let caskFullName = "block/tap/qrgo-app"
    static let caskToken = "qrgo-app"

    private static let lockContext = "QRGo is checking for updates in the background."
    private static let updateLockUnavailableMessage = "Another Homebrew update is already running."

    let mayUnloadLaunchAgentDuringInstall = true

    private let commandRunner: MenuBarUpdateCommandRunning
    private let executableResolver: HomebrewExecutableResolving
    private var refreshStore: HomebrewUpdateRefreshStoring
    private let lockProbe: HomebrewUpdateLockProbing
    private let refreshLease: QRGoHomebrewRefreshLeasing
    private let environment: [String: String]
    private let dateProvider: () -> Date
    private let refreshInterval: TimeInterval
    private let staleMetadataInterval: TimeInterval
    private let refreshTimeout: TimeInterval
    private let checkTimeout: TimeInterval
    private let installTimeout: TimeInterval
    private let log: (String) -> Void
    private let logError: (String) -> Void

    init(
        commandRunner: MenuBarUpdateCommandRunning = IsolatedMenuBarUpdateCommandRunner(),
        executableResolver: HomebrewExecutableResolving = HomebrewExecutableResolver(),
        refreshStore: HomebrewUpdateRefreshStoring = UserDefaultsHomebrewUpdateRefreshStore(),
        lockProbe: HomebrewUpdateLockProbing = DarwinHomebrewUpdateLockProbe(),
        refreshLease: QRGoHomebrewRefreshLeasing = FileQRGoHomebrewRefreshLease(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        dateProvider: @escaping () -> Date = Date.init,
        refreshInterval: TimeInterval = 24 * 60 * 60,
        staleMetadataInterval: TimeInterval = 7 * 24 * 60 * 60,
        refreshTimeout: TimeInterval = 5 * 60,
        checkTimeout: TimeInterval = 60,
        installTimeout: TimeInterval = 15 * 60,
        log: @escaping (String) -> Void = QRGoLogger.menuBarInfo,
        logError: @escaping (String) -> Void = QRGoLogger.menuBarError
    ) {
        self.commandRunner = commandRunner
        self.executableResolver = executableResolver
        self.refreshStore = refreshStore
        self.lockProbe = lockProbe
        self.refreshLease = refreshLease
        self.environment = environment
        self.dateProvider = dateProvider
        self.refreshInterval = refreshInterval
        self.staleMetadataInterval = staleMetadataInterval
        self.refreshTimeout = refreshTimeout
        self.checkTimeout = checkTimeout
        self.installTimeout = installTimeout
        self.log = log
        self.logError = logError
    }

    func checkForUpdate(mode: MenuBarUpdateCheckMode) async -> MenuBarUpdateCheckResult {
        var service = self
        service.log("Checking QRGo Homebrew update state in \(mode.diagnosticName) mode.")
        if mode == .refreshIfDue {
            let refreshResult = await service.refreshHomebrewMetadataIfNeeded()
            switch refreshResult {
            case .continueToOutdatedCheck:
                break
            case .unavailable(let message):
                service.logStaleMetadataIfNeeded()
                return .unavailable(message)
            case .failed(let error):
                service.logStaleMetadataIfNeeded()
                return .failed(error)
            }
        }

        service.logStaleMetadataIfNeeded()
        return await service.checkOutdatedCask()
    }

    func installUpdate() async -> MenuBarUpdateInstallResult {
        guard let brewExecutablePath = await executableResolver.brewExecutablePath() else {
            return .failed(MenuBarUpdateCommandError(
                message: "Homebrew is not available.",
                details: "",
                timedOut: false
            ))
        }

        log("Starting QRGo Homebrew cask upgrade.")
        let result = await commandRunner.run(
            executable: brewExecutablePath,
            arguments: ["upgrade", "--cask", Self.caskFullName],
            environment: homebrewEnvironment([
                "HOMEBREW_NO_AUTO_UPDATE": "1",
                "HOMEBREW_NO_ENV_HINTS": "1",
                "HOMEBREW_NO_INSTALL_CLEANUP": "1"
            ]),
            timeout: installTimeout,
            description: "brew upgrade --cask \(Self.caskFullName)"
        )
        log("Finished QRGo Homebrew cask upgrade with exit code \(result.exitCode).")

        guard result.succeeded else {
            return .failed(commandError(
                message: installErrorMessage(from: result),
                result: result
            ))
        }
        return .installed
    }

    static func checkResult(fromOutdatedJSON json: String) throws -> MenuBarUpdateCheckResult {
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(HomebrewOutdatedResponse.self, from: data)
        guard let cask = response.casks.first(where: { $0.name == caskToken }) else {
            return .current
        }

        return .available(MenuBarUpdate(
            installedVersion: cask.installedVersions.first ?? "unknown",
            currentVersion: cask.currentVersion
        ))
    }
}

private extension HomebrewUpdateService {
    private mutating func refreshHomebrewMetadataIfNeeded() async -> MetadataRefreshResult {
        if backgroundRefreshIsDisabled {
            log("Skipping QRGo Homebrew metadata refresh: disabled by environment.")
            return .continueToOutdatedCheck
        }

        let now = dateProvider()
        if let lastAttempt = refreshStore.lastRefreshAttemptAt,
           now.timeIntervalSince(lastAttempt) < refreshInterval {
            log("Skipping QRGo Homebrew metadata refresh: throttled.")
            return .continueToOutdatedCheck
        }
        recordRefreshAttempt(now: now)

        guard let brewExecutablePath = await executableResolver.brewExecutablePath() else {
            refreshStore.lastRefreshFailureReason = "Homebrew is not available."
            return .unavailable("Homebrew is not available.")
        }
        guard let homebrewPrefix = await executableResolver.homebrewPrefix(
            brewExecutablePath: brewExecutablePath
        ) else {
            refreshStore.lastRefreshFailureReason = "Homebrew is not available."
            return .unavailable("Homebrew is not available.")
        }

        switch refreshLease.acquire(mode: "refreshIfDue", now: now) {
        case .acquired(let lease):
            defer {
                refreshLease.release(lease)
            }
            return await refreshHomebrewMetadata(
                brewExecutablePath: brewExecutablePath,
                homebrewPrefix: homebrewPrefix
            )
        case .unavailable(let reason):
            log("Skipping QRGo Homebrew metadata refresh: \(reason)")
            refreshStore.lastRefreshFailureReason = reason
            return .unavailable("QRGo is already checking for Homebrew updates.")
        }
    }

    private mutating func refreshHomebrewMetadata(
        brewExecutablePath: String,
        homebrewPrefix: String
    ) async -> MetadataRefreshResult {
        switch lockProbe.updateLockState(homebrewPrefix: homebrewPrefix) {
        case .unlocked:
            break
        case .held(let holder):
            log("Skipping QRGo Homebrew metadata refresh: Homebrew update lock is held.\(holderSuffix(holder))")
            refreshStore.lastRefreshFailureReason = "Homebrew update lock is held."
            return .unavailable(Self.updateLockUnavailableMessage)
        case .unavailable(let message):
            log("Skipping QRGo Homebrew metadata refresh: \(message)")
            refreshStore.lastRefreshFailureReason = message
            return .unavailable(Self.updateLockUnavailableMessage)
        }

        log("Starting QRGo Homebrew metadata refresh.")

        let updateIfNeededResult = await runMetadataRefreshCommand(
            brewExecutablePath: brewExecutablePath,
            arguments: ["update-if-needed"],
            description: "brew update-if-needed"
        )
        if updateIfNeededResult.succeeded {
            recordRefreshSuccess()
            return .continueToOutdatedCheck
        }
        if lockContentionMessage(from: updateIfNeededResult) {
            recordRefreshFailure("Homebrew update lock is held.")
            return .unavailable(Self.updateLockUnavailableMessage)
        }
        if updateIfNeededResult.timedOut || updateIfNeededResult.cancelled {
            recordRefreshFailure(timeoutAwareMessage(
                "Could not update Homebrew metadata.",
                result: updateIfNeededResult
            ))
            if updateIfNeededResult.cancelled {
                return .failed(commandError(
                    message: "Could not update Homebrew metadata.",
                    result: updateIfNeededResult
                ))
            }
            return .continueToOutdatedCheck
        }
        if updateIfNeededIsUnavailable(from: updateIfNeededResult) {
            log("Homebrew update-if-needed is unavailable; falling back to brew update --auto-update --quiet.")
            let fallbackResult = await runMetadataRefreshCommand(
                brewExecutablePath: brewExecutablePath,
                arguments: ["update", "--auto-update", "--quiet"],
                description: "brew update --auto-update --quiet"
            )
            if fallbackResult.succeeded {
                recordRefreshSuccess()
                return .continueToOutdatedCheck
            }
            if lockContentionMessage(from: fallbackResult) {
                recordRefreshFailure("Homebrew update lock is held.")
                return .unavailable(Self.updateLockUnavailableMessage)
            }
            recordRefreshFailure(timeoutAwareMessage("Could not update Homebrew metadata.", result: fallbackResult))
            if fallbackResult.cancelled {
                return .failed(commandError(
                    message: "Could not update Homebrew metadata.",
                    result: fallbackResult
                ))
            }
            return .continueToOutdatedCheck
        }

        recordRefreshFailure(timeoutAwareMessage("Could not update Homebrew metadata.", result: updateIfNeededResult))
        return .continueToOutdatedCheck
    }

    private func runMetadataRefreshCommand(
        brewExecutablePath: String,
        arguments: [String],
        description: String
    ) async -> ShellResult {
        log("Starting QRGo Homebrew command: \(description).")
        let result = await commandRunner.run(
            executable: brewExecutablePath,
            arguments: arguments,
            environment: homebrewEnvironment([
                "HOMEBREW_LOCK_CONTEXT": Self.lockContext,
                "HOMEBREW_NO_ENV_HINTS": "1"
            ]),
            timeout: refreshTimeout,
            description: description
        )
        log("Finished QRGo Homebrew command: \(description) with exit code \(result.exitCode).")
        return result
    }

    private func checkOutdatedCask() async -> MenuBarUpdateCheckResult {
        guard let brewExecutablePath = await executableResolver.brewExecutablePath() else {
            return .unavailable("Homebrew is not available.")
        }

        let description = "brew outdated --cask --json=v2 \(Self.caskFullName)"
        log("Starting QRGo Homebrew command: \(description).")
        let result = await commandRunner.run(
            executable: brewExecutablePath,
            arguments: ["outdated", "--cask", "--json=v2", Self.caskFullName],
            environment: homebrewEnvironment(["HOMEBREW_NO_AUTO_UPDATE": "1"]),
            timeout: checkTimeout,
            description: description
        )
        log("Finished QRGo Homebrew command: \(description) with exit code \(result.exitCode).")
        if let unavailableMessage = unavailableMessage(from: result) {
            return .unavailable(unavailableMessage)
        }

        do {
            let checkResult = try Self.checkResult(fromOutdatedJSON: result.stdout)
            if result.succeeded || checkResult.hasAvailableUpdate {
                return checkResult
            }
        } catch {
            return .failed(commandError(
                message: "Homebrew returned invalid update information.",
                result: result
            ))
        }

        return .failed(commandError(
            message: "Could not check for QRGo updates.",
            result: result
        ))
    }

    private mutating func recordRefreshAttempt(now: Date) {
        if refreshStore.firstRefreshAttemptWithoutSuccessAt == nil {
            refreshStore.firstRefreshAttemptWithoutSuccessAt = now
        }
        refreshStore.lastRefreshAttemptAt = now
    }

    private mutating func recordRefreshSuccess() {
        refreshStore.lastRefreshSucceededAt = dateProvider()
        refreshStore.lastRefreshFailureReason = nil
        refreshStore.firstRefreshAttemptWithoutSuccessAt = nil
        log("Finished QRGo Homebrew metadata refresh.")
    }

    private mutating func recordRefreshFailure(_ reason: String) {
        refreshStore.lastRefreshFailureReason = reason
        logError("QRGo Homebrew metadata refresh failed: \(reason)")
    }

    private func logStaleMetadataIfNeeded() {
        let referenceDate = refreshStore.lastRefreshSucceededAt ??
            refreshStore.firstRefreshAttemptWithoutSuccessAt ??
            refreshStore.lastRefreshAttemptAt
        guard let referenceDate = referenceDate else {
            return
        }
        let age = dateProvider().timeIntervalSince(referenceDate)
        if age >= staleMetadataInterval {
            log("QRGo Homebrew metadata has not refreshed successfully for \(Int(age / 86_400)) day(s).")
        }
    }

    private var backgroundRefreshIsDisabled: Bool {
        environment["QRGO_DISABLE_BACKGROUND_HOMEBREW_REFRESH"] == "1" ||
            environment["HOMEBREW_NO_AUTO_UPDATE"] == "1"
    }

    private func homebrewEnvironment(_ overrides: [String: String]) -> [String: String] {
        environment.merging(overrides) { _, new in new }
    }

    private func holderSuffix(_ holder: String?) -> String {
        guard let holder = holder, !holder.isEmpty else {
            return ""
        }
        return " Holder: \(holder)"
    }

    private func commandError(message: String, result: ShellResult) -> MenuBarUpdateCommandError {
        let details = [result.stdout, result.stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return MenuBarUpdateCommandError(
            message: timeoutAwareMessage(message, result: result),
            details: details,
            timedOut: result.timedOut
        )
    }

    private func timeoutAwareMessage(_ message: String, result: ShellResult) -> String {
        if result.cancelled {
            return "\(message) The command was cancelled."
        }
        guard result.timedOut else {
            return message
        }

        let lowercasedMessage = message.lowercased()
        if lowercasedMessage.contains("timed out") || lowercasedMessage.contains("too long") {
            return message
        }
        return "\(message) The command timed out."
    }

    private func unavailableMessage(from result: ShellResult) -> String? {
        let output = "\(result.stdout)\n\(result.stderr)".lowercased()
        if output.contains("command not found: brew") ||
            output.contains("brew: command not found") ||
            output.contains("no such file or directory") {
            return "Homebrew is not available."
        }
        if lockContentionMessage(from: result) {
            return Self.updateLockUnavailableMessage
        }
        if output.contains("cask") && output.contains(Self.caskToken) &&
            (output.contains("is not installed") ||
             output.contains("not installed") ||
             output.contains("unavailable") ||
             output.contains("no available cask")) {
            return "The QRGo Homebrew cask is not installed."
        }
        return nil
    }

    private func lockContentionMessage(from result: ShellResult) -> Bool {
        let output = "\(result.stdout)\n\(result.stderr)".lowercased()
        return output.contains("lockf: 200: already locked") ||
            output.contains("another `brew update` process is already running") ||
            output.contains("another brew update process is already running")
    }

    private func updateIfNeededIsUnavailable(from result: ShellResult) -> Bool {
        let output = "\(result.stdout)\n\(result.stderr)".lowercased()
        return output.contains("unknown command") ||
            output.contains("invalid command") ||
            output.contains("no available command") ||
            output.contains("unrecognized command")
    }

    private func installErrorMessage(from result: ShellResult) -> String {
        if result.timedOut {
            return "The update took too long and was stopped."
        }
        if result.cancelled {
            return "The update was stopped."
        }

        let output = "\(result.stdout)\n\(result.stderr)".lowercased()
        if output.contains("sudo") ||
            output.contains("password") ||
            output.contains("a terminal is required") ||
            output.contains("not a tty") ||
            output.contains("no tty") {
            return "Homebrew needs terminal access to finish the update."
        }

        return "Could not install the QRGo update."
    }
}

private extension MenuBarUpdateCheckMode {
    var diagnosticName: String {
        switch self {
        case .passive:
            return "passive"
        case .refreshIfDue:
            return "refreshIfDue"
        }
    }
}

private enum MetadataRefreshResult {
    case continueToOutdatedCheck
    case unavailable(String)
    case failed(MenuBarUpdateCommandError)
}

private struct HomebrewOutdatedResponse: Decodable {
    let casks: [HomebrewOutdatedCask]
}

private struct HomebrewOutdatedCask: Decodable {
    let name: String
    let installedVersions: [String]
    let currentVersion: String

    enum CodingKeys: String, CodingKey {
        case name
        case installedVersions = "installed_versions"
        case currentVersion = "current_version"
    }
}
