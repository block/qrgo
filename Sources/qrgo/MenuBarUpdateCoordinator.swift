import AppKit
import Foundation

/// Coordinates menu bar update checks with user-visible session and app-idle state.
@MainActor
final class MenuBarUpdateCoordinator {
    private enum CheckReason {
        case launch
        case daily
    }

    private let service: MenuBarUpdateServicing
    private let dailyInterval: TimeInterval
    private let isIdleProvider: () -> Bool
    private let presentUpdate: (MenuBarUpdate) -> Void
    private let log: (String) -> Void
    private let logError: (String) -> Void
    private let isLoginItemInstalled: () -> Bool
    private let isCurrentProcessManagedByLoginItem: () -> Bool
    private let installLoginItem: () -> Bool

    private var dailyTimer: Timer?
    private var isChecking = false
    private var isInstalling = false
    private var pendingDailyCheck = false
    private var pendingUpdate: MenuBarUpdate?
    private var lastPromptedVersion: String?
    private var sessionIsActive: Bool
    private var screensAreAwake = true

    init(
        service: MenuBarUpdateServicing,
        dailyInterval: TimeInterval = 24 * 60 * 60,
        isIdleProvider: @escaping () -> Bool,
        presentUpdate: @escaping (MenuBarUpdate) -> Void,
        log: @escaping (String) -> Void = QRGoLogger.menuBarInfo,
        logError: @escaping (String) -> Void = QRGoLogger.menuBarError,
        isLoginItemInstalled: @escaping () -> Bool = { LoginItemHelper.isInstalled },
        isCurrentProcessManagedByLoginItem: @escaping () -> Bool = { LoginItemHelper.isManagingCurrentProcess },
        installLoginItem: @escaping () -> Bool = { LoginItemHelper.install(loadImmediately: false) }
    ) {
        self.service = service
        self.dailyInterval = dailyInterval
        self.isIdleProvider = isIdleProvider
        self.presentUpdate = presentUpdate
        self.log = log
        self.logError = logError
        self.isLoginItemInstalled = isLoginItemInstalled
        self.isCurrentProcessManagedByLoginItem = isCurrentProcessManagedByLoginItem
        self.installLoginItem = installLoginItem
        sessionIsActive = Self.currentSessionIsActive()
    }

    deinit {
        dailyTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func start() {
        installWorkspaceObservers()
        startCheck(reason: .launch)
    }

    func installUpdate() async -> MenuBarUpdateInstallResult {
        guard !isInstalling else {
            return .failed(MenuBarUpdateCommandError(
                message: "An update is already installing.",
                details: "",
                timedOut: false
            ))
        }
        guard !service.mayUnloadLaunchAgentDuringInstall || !isCurrentProcessManagedByLoginItem() else {
            return .failed(MenuBarUpdateCommandError(
                message: "QRGo was started at login. Quit QRGo, open it from Applications, then retry the update.",
                details: "Homebrew unloads the launch-at-login job during cask upgrades.",
                timedOut: false
            ))
        }

        let shouldRestoreLoginItem = isLoginItemInstalled()
        isInstalling = true
        defer {
            isInstalling = false
            drainDeferredWork()
        }

        let result = await service.installUpdate()
        restoreLoginItemIfNeeded(after: result, wasInstalled: shouldRestoreLoginItem)
        return result
    }

    func idleStateDidChange() {
        drainDeferredWork()
    }

    func dailyCheckBecameDueForTesting() {
        dailyCheckBecameDue()
    }

    func screenDidSleepForTesting() {
        screensAreAwake = false
    }

    func screenDidWakeForTesting() {
        screensAreAwake = true
        drainDeferredWork()
    }

    func sessionDidResignActiveForTesting() {
        sessionIsActive = false
    }

    func sessionDidBecomeActiveForTesting() {
        sessionIsActive = true
        drainDeferredWork()
    }

    private func installWorkspaceObservers() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        notificationCenter.addObserver(
            self,
            selector: #selector(screenDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(screenDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(sessionDidResignActive),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(sessionDidBecomeActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func screenDidSleep() {
        screensAreAwake = false
    }

    @objc private func screenDidWake() {
        screensAreAwake = true
        drainDeferredWork()
    }

    @objc private func sessionDidResignActive() {
        sessionIsActive = false
    }

    @objc private func sessionDidBecomeActive() {
        sessionIsActive = true
        drainDeferredWork()
    }

    private func dailyCheckBecameDue() {
        dailyTimer?.invalidate()
        dailyTimer = nil

        // A daily check is allowed to become overdue; it should run when a toast can actually be seen.
        guard canRunDailyCheck else {
            pendingDailyCheck = true
            return
        }

        startCheck(reason: .daily)
    }

    private func startCheck(reason: CheckReason) {
        guard !isChecking, !isInstalling else {
            if reason == .daily {
                pendingDailyCheck = true
            }
            return
        }

        if reason == .daily, !canRunDailyCheck {
            pendingDailyCheck = true
            return
        }

        isChecking = true
        Task { [weak self] in
            guard let self = self else { return }
            let result = await self.service.checkForUpdate()
            self.handleCheckResult(result)
        }
    }

    private func handleCheckResult(_ result: MenuBarUpdateCheckResult) {
        isChecking = false
        scheduleNextDailyCheck()

        switch result {
        case .current:
            log("QRGo is up to date.")
        case .available(let update):
            log("QRGo update available: \(update.installedVersion) -> \(update.currentVersion)")
            presentOrDefer(update)
        case .unavailable(let message):
            log("Skipping QRGo update check: \(message)")
        case .failed(let error):
            logError("QRGo update check failed: \(error.message) \(error.details)")
        }

        drainDeferredWork()
    }

    private func scheduleNextDailyCheck() {
        dailyTimer?.invalidate()
        dailyTimer = Timer.scheduledTimer(withTimeInterval: dailyInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.dailyCheckBecameDue()
            }
        }
    }

    private func presentOrDefer(_ update: MenuBarUpdate) {
        guard lastPromptedVersion != update.currentVersion else {
            return
        }

        // Keep transient update prompts out of active QR scanning, settings, or installer workflows.
        guard canPresentUpdate else {
            pendingUpdate = update
            return
        }

        lastPromptedVersion = update.currentVersion
        presentUpdate(update)
    }

    private func drainDeferredWork() {
        if let update = pendingUpdate, canPresentUpdate {
            pendingUpdate = nil
            presentOrDefer(update)
        }

        if pendingDailyCheck, canRunDailyCheck {
            pendingDailyCheck = false
            startCheck(reason: .daily)
        }
    }

    private func restoreLoginItemIfNeeded(after result: MenuBarUpdateInstallResult, wasInstalled: Bool) {
        guard case .installed = result,
              wasInstalled,
              !isLoginItemInstalled() else {
            return
        }

        // Homebrew cask upgrades may run uninstall cleanup that removes our LaunchAgent plist.
        if installLoginItem() {
            log("Restored QRGo launch-at-login after update.")
        } else {
            logError("Failed to restore QRGo launch-at-login after update.")
        }
    }

    private var canRunDailyCheck: Bool {
        sessionIsActive && screensAreAwake && isIdleProvider() && !isInstalling
    }

    private var canPresentUpdate: Bool {
        canRunDailyCheck && !isChecking
    }

    private static func currentSessionIsActive() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let screenIsLocked = session["CGSSessionScreenIsLocked"] as? Bool else {
            return true
        }
        return !screenIsLocked
    }
}
