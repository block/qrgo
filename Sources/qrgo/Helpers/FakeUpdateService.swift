import Foundation

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

    func checkForUpdate(mode _: MenuBarUpdateCheckMode) async -> MenuBarUpdateCheckResult {
        await sleep(for: checkDelay)

        if let invalidMode = invalidMode {
            return .failed(MenuBarUpdateCommandError(
                message: "Unknown QRGo update dry-run mode.",
                details: "QRGO_UPDATE_DRY_RUN=\(invalidMode)",
                timedOut: false
            ))
        }

        switch self.mode {
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

private extension Dictionary where Key == String, Value == String {
    func timeInterval(forKey key: String) -> TimeInterval? {
        guard let value = self[key] else {
            return nil
        }
        return TimeInterval(value)
    }
}
