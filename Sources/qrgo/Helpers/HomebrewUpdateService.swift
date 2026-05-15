import Foundation

/// Version pair reported by Homebrew when the QRGo cask is outdated.
struct MenuBarUpdate: Equatable {
    let installedVersion: String
    let currentVersion: String
}

/// Result of a background menu bar update check.
enum MenuBarUpdateCheckResult: Equatable {
    case current
    case available(MenuBarUpdate)
    case unavailable(String)
    case failed(MenuBarUpdateCommandError)
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

    func checkForUpdate() async -> MenuBarUpdateCheckResult
    func installUpdate() async -> MenuBarUpdateInstallResult
}

extension MenuBarUpdateServicing {
    var mayUnloadLaunchAgentDuringInstall: Bool { false }
}

/// Runs update commands through a login shell so Homebrew is found on the user's PATH.
protocol MenuBarUpdateCommandRunning {
    func runLoginShell(_ command: String, timeout: TimeInterval) async -> ShellResult
}

struct ShellMenuBarUpdateCommandRunner: MenuBarUpdateCommandRunning {
    func runLoginShell(_ command: String, timeout: TimeInterval) async -> ShellResult {
        await Task.detached {
            Shell.runLoginShell(command, timeout: timeout, suppressStderr: false)
        }.value
    }
}

/// Production update service backed by the `block/tap/qrgo-app` Homebrew cask.
struct HomebrewUpdateService: MenuBarUpdateServicing {
    static let caskFullName = "block/tap/qrgo-app"
    static let caskToken = "qrgo-app"

    let mayUnloadLaunchAgentDuringInstall = true

    private let commandRunner: MenuBarUpdateCommandRunning
    private let checkTimeout: TimeInterval
    private let installTimeout: TimeInterval

    init(
        commandRunner: MenuBarUpdateCommandRunning = ShellMenuBarUpdateCommandRunner(),
        checkTimeout: TimeInterval = 60,
        installTimeout: TimeInterval = 15 * 60
    ) {
        self.commandRunner = commandRunner
        self.checkTimeout = checkTimeout
        self.installTimeout = installTimeout
    }

    func checkForUpdate() async -> MenuBarUpdateCheckResult {
        let updateResult = await commandRunner.runLoginShell(
            "exec brew update --auto-update --quiet",
            timeout: checkTimeout
        )
        if let unavailableMessage = unavailableMessage(from: updateResult) {
            return .unavailable(unavailableMessage)
        }
        guard updateResult.succeeded else {
            return .failed(commandError(
                message: "Could not update Homebrew metadata.",
                result: updateResult
            ))
        }

        let outdatedResult = await commandRunner.runLoginShell(
            "exec brew outdated --cask --json=v2 \(Self.caskFullName)",
            timeout: checkTimeout
        )
        if let unavailableMessage = unavailableMessage(from: outdatedResult) {
            return .unavailable(unavailableMessage)
        }
        guard outdatedResult.succeeded else {
            return .failed(commandError(
                message: "Could not check for QRGo updates.",
                result: outdatedResult
            ))
        }

        do {
            return try Self.checkResult(fromOutdatedJSON: outdatedResult.stdout)
        } catch {
            return .failed(commandError(
                message: "Homebrew returned invalid update information.",
                result: outdatedResult
            ))
        }
    }

    func installUpdate() async -> MenuBarUpdateInstallResult {
        let result = await commandRunner.runLoginShell(
            "exec brew upgrade --cask \(Self.caskFullName)",
            timeout: installTimeout
        )
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
        if output.contains("cask") && output.contains(Self.caskToken) &&
            (output.contains("is not installed") ||
             output.contains("not installed") ||
             output.contains("unavailable") ||
             output.contains("no available cask")) {
            return "The QRGo Homebrew cask is not installed."
        }
        return nil
    }

    private func installErrorMessage(from result: ShellResult) -> String {
        if result.timedOut {
            return "The update took too long and was stopped."
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

/// Development-only service used to exercise update UI states without invoking Homebrew.
struct FakeUpdateService: MenuBarUpdateServicing {
    enum Mode: String {
        case current
        case available
        case checkError = "check-error"
        case installError = "install-error"
    }

    private let mode: Mode
    private let invalidMode: String?
    private let checkDelay: TimeInterval
    private let installDelay: TimeInterval

    init(mode: Mode, invalidMode: String? = nil, checkDelay: TimeInterval = 2, installDelay: TimeInterval = 5) {
        self.mode = mode
        self.invalidMode = invalidMode
        self.checkDelay = checkDelay
        self.installDelay = installDelay
    }

    func checkForUpdate() async -> MenuBarUpdateCheckResult {
        await sleep(for: checkDelay)

        if let invalidMode = invalidMode {
            return .failed(MenuBarUpdateCommandError(
                message: "Unknown QRGo update dry-run mode.",
                details: "QRGO_UPDATE_DRY_RUN=\(invalidMode)",
                timedOut: false
            ))
        }

        switch mode {
        case .current:
            return .current
        case .available, .installError:
            return .available(MenuBarUpdate(installedVersion: "1.0.0", currentVersion: "9.9.9"))
        case .checkError:
            return .failed(MenuBarUpdateCommandError(
                message: "Dry-run update check failed.",
                details: "QRGO_UPDATE_DRY_RUN=check-error",
                timedOut: false
            ))
        }
    }

    func installUpdate() async -> MenuBarUpdateInstallResult {
        await sleep(for: installDelay)

        switch mode {
        case .installError:
            return .failed(MenuBarUpdateCommandError(
                message: "Dry-run update install failed.",
                details: "QRGO_UPDATE_DRY_RUN=install-error",
                timedOut: false
            ))
        case .current, .available, .checkError:
            return .installed
        }
    }

    static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> FakeUpdateService? {
        guard let rawMode = environment["QRGO_UPDATE_DRY_RUN"] else {
            return nil
        }
        let mode = Mode(rawValue: rawMode) ?? .checkError

        return FakeUpdateService(
            mode: mode,
            invalidMode: Mode(rawValue: rawMode) == nil ? rawMode : nil,
            checkDelay: environment.timeInterval(forKey: "QRGO_UPDATE_CHECK_DELAY_SECONDS") ?? 2,
            installDelay: environment.timeInterval(forKey: "QRGO_UPDATE_INSTALL_DELAY_SECONDS") ?? 5
        )
    }

    private func sleep(for delay: TimeInterval) async {
        guard delay > 0 else {
            return
        }
        let nanoseconds = UInt64(delay * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }
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

private extension Dictionary where Key == String, Value == String {
    func timeInterval(forKey key: String) -> TimeInterval? {
        guard let value = self[key] else {
            return nil
        }
        return TimeInterval(value)
    }
}
