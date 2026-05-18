import AppKit
import Foundation

enum MenuBarApp {
    @MainActor
    static func run(configuration: QRGoRunConfiguration) {
        guard let lock = MenuBarInstanceLock.acquire() else {
            QRGoLogger.menuBarInfo("QRGo menu bar app is already running.")
            return
        }
        instanceLock = lock

        QRGoLogger.menuBarInfo("Starting QRGo menu bar app.")

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let delegate = MenuBarAppDelegate(configuration: configuration)
        app.delegate = delegate

        withExtendedLifetime(delegate) {
            app.run()
        }
    }

    private static var instanceLock: MenuBarInstanceLock?
}

@MainActor
final class MenuBarAppDelegate: NSObject, NSApplicationDelegate {
    private let controller: MenuBarController

    init(configuration: QRGoRunConfiguration) {
        controller = MenuBarController(configuration: configuration)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.installStatusItem()
    }
}

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let configuration: QRGoRunConfiguration
    private let notifier = MenuBarNotifier()
    private lazy var targetSelector = AppKitTargetSelector(notifier: notifier)
    private lazy var shortcutManager = GlobalKeyboardShortcutManager { [weak self] in
        self?.startScan()
    }
    private var isRunningAction = false
    private var registeredShortcut: KeyboardShortcut?
    private var settingsWindowController: MenuBarSettingsWindowController?
    private var updateCoordinator: MenuBarUpdateCoordinator?
    private var updateInstallWindowController: MenuBarUpdateInstallWindowController?
    private var statusItem: NSStatusItem?

    init(configuration: QRGoRunConfiguration) {
        self.configuration = configuration
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scanShortcutDidChange),
            name: MenuBarSettingsStore.scanShortcutDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func installStatusItem() {
        QRGoLogger.menuBarInfo("Installing QRGo status item.")

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "qrcode.viewfinder", accessibilityDescription: "QRGo") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "QR"
            }
            button.toolTip = "QRGo"
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            notifier.anchorView = button
            targetSelector.anchorView = button
        }
        self.statusItem = statusItem
        applyScanShortcut()
        installUpdateCoordinator()
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else if targetSelector.isShowingChooser {
            targetSelector.refocusChooser()
        } else {
            startScan()
        }
    }

    @objc private func startScan() {
        guard canRunQRGoAction else {
            notifier.warning("QRGo is already busy.")
            return
        }

        QRGoLogger.menuBarInfo("Starting QR scan from menu bar.")
        isRunningAction = true
        updateCoordinator?.idleStateDidChange()
        Task { @MainActor in
            defer {
                isRunningAction = false
                updateCoordinator?.idleStateDidChange()
            }
            let runner = QRGoRunner(
                configuration: configuration,
                targetSelector: targetSelector,
                notifier: notifier
            )
            _ = await runner.run()
        }
    }

    @objc private func openLastScan() {
        guard canRunQRGoAction else {
            notifier.warning("QRGo is already busy.")
            return
        }

        QRGoLogger.menuBarInfo("Opening last scanned QR code from menu bar.")
        isRunningAction = true
        updateCoordinator?.idleStateDidChange()
        Task { @MainActor in
            defer {
                isRunningAction = false
                updateCoordinator?.idleStateDidChange()
            }
            let runner = QRGoRunner(
                configuration: configuration,
                targetSelector: targetSelector,
                notifier: notifier
            )
            _ = await runner.openLastScan()
        }
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = MenuBarSettingsWindowController(
                registeredShortcutProvider: { [weak self] in
                    self?.registeredShortcut
                },
                onClose: { [weak self] in
                    self?.updateCoordinator?.idleStateDidChange()
                }
            )
        }
        settingsWindowController?.showWindow(nil)
        updateCoordinator?.idleStateDidChange()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func scanShortcutDidChange() {
        applyScanShortcut()
    }

    private func showMenu() {
        guard let statusItem = statusItem else { return }

        let menu = NSMenu()
        // AppKit auto-enables items with valid actions, which would override the last-scan disabled state.
        menu.autoenablesItems = false
        let scanShortcut = MenuBarSettingsStore.scanShortcut
        let scanItem = NSMenuItem(
            title: "Scan QR Code",
            action: #selector(startScan),
            keyEquivalent: scanShortcut.menuKeyEquivalent
        )
        scanItem.keyEquivalentModifierMask = scanShortcut.menuModifierMask
        scanItem.isEnabled = canRunQRGoAction
        menu.addItem(scanItem)

        let openLastItem = NSMenuItem(title: "Open Last QR Code", action: #selector(openLastScan), keyEquivalent: "")
        openLastItem.isEnabled = LastScanStore.hasLastScan && canRunQRGoAction
        menu.addItem(openLastItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.image = nil
        settingsItem.isEnabled = canRunQRGoAction
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit QRGo", action: #selector(quit), keyEquivalent: "q")
        quitItem.isEnabled = updateInstallWindowController?.isInstalling != true
        menu.addItem(quitItem)
        menu.delegate = self

        for item in menu.items {
            item.target = self
        }

        // Attach the menu only while AppKit is tracking this click so normal left-clicks keep scanning.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    private func installUpdateCoordinator() {
        let updateCoordinator = MenuBarUpdateCoordinator(
            service: Self.makeUpdateService(),
            isIdleProvider: { [weak self] in
                self?.isIdleForUpdatePresentation ?? false
            },
            presentUpdate: { [weak self] update in
                self?.notifier.updateAvailable(update) { [weak self] in
                    self?.openUpdateInstaller(for: update)
                }
            }
        )
        self.updateCoordinator = updateCoordinator
        updateCoordinator.start()
    }

    private func openUpdateInstaller(for update: MenuBarUpdate) {
        if let updateInstallWindowController = updateInstallWindowController,
           updateInstallWindowController.window?.isVisible == true {
            updateInstallWindowController.showWindow(nil)
            return
        }

        let updateInstallWindowController = MenuBarUpdateInstallWindowController(
            update: update,
            installHandler: { [weak self] in
                guard let updateCoordinator = self?.updateCoordinator else {
                    return .failed(MenuBarUpdateCommandError(
                        message: "The update installer is unavailable.",
                        details: "",
                        timedOut: false
                    ))
                }
                return await updateCoordinator.installUpdate()
            },
            onClose: { [weak self] in
                self?.updateInstallWindowController = nil
                self?.updateCoordinator?.idleStateDidChange()
            }
        )
        self.updateInstallWindowController = updateInstallWindowController
        updateInstallWindowController.showWindow(nil)
        updateCoordinator?.idleStateDidChange()
    }

    private var isIdleForUpdatePresentation: Bool {
        !isRunningAction &&
            settingsWindowController?.window?.isVisible != true &&
            updateInstallWindowController?.window?.isVisible != true
    }

    private var canRunQRGoAction: Bool {
        !isRunningAction && updateInstallWindowController?.window?.isVisible != true
    }

    private static func makeUpdateService() -> MenuBarUpdateServicing {
        if let fakeUpdateService = FakeUpdateService.fromEnvironment() {
            QRGoLogger.menuBarInfo("Using QRGo dry-run update service.")
            return fakeUpdateService
        }
        return HomebrewUpdateService()
    }

    private func applyScanShortcut() {
        let shortcut = MenuBarSettingsStore.scanShortcut
        if let message = KeyboardShortcutValidator.validationMessage(
            for: shortcut,
            currentShortcut: registeredShortcut
        ) {
            QRGoLogger.menuBarWarning("Scan keyboard shortcut disabled: \(message)")
            notifier.warning("Keyboard shortcut disabled. Change it in Settings.")
            return
        }

        let previousShortcut = registeredShortcut
        // Keep the last working hotkey active if a saved setting becomes unavailable at registration time.
        let status = shortcutManager.register(shortcut: shortcut)
        guard status == noErr else {
            restorePreviousShortcut(previousShortcut)
            QRGoLogger.menuBarWarning("Failed to register scan keyboard shortcut: \(status)")
            notifier.warning("Keyboard shortcut unavailable. Change it in Settings.")
            return
        }

        registeredShortcut = shortcut
        QRGoLogger.menuBarInfo("Registered scan keyboard shortcut \(shortcut.displayString).")
    }

    private func restorePreviousShortcut(_ previousShortcut: KeyboardShortcut?) {
        guard let previousShortcut = previousShortcut else {
            registeredShortcut = nil
            return
        }

        let status = shortcutManager.register(shortcut: previousShortcut)
        registeredShortcut = status == noErr ? previousShortcut : nil
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem?.menu = nil
    }
}

/// Adapts target selection to the menu-bar app's status-item anchored popover.
///
/// The selector is retained by `MenuBarController` across scans so a second status-item click can refocus the visible
/// chooser instead of starting another scan or replacing it with a busy toast.
@MainActor
final class AppKitTargetSelector: QRGoTargetSelecting {
    weak var anchorView: NSView?

    private weak var notifier: MenuBarNotifier?
    private var chooserPresenter: TargetChooserPopoverPresenter?

    var isShowingChooser: Bool {
        chooserPresenter?.isShowing == true
    }

    init(notifier: MenuBarNotifier) {
        self.notifier = notifier
    }

    func selectTarget(
        for urlString: String,
        from options: [TargetOption],
        footerWarning: String?
    ) async -> TargetAction? {
        NSApp.activate(ignoringOtherApps: true)
        guard let anchorView = anchorView, anchorView.window != nil else {
            NSSound.beep()
            return nil
        }

        notifier?.dismissVisibleToast()
        chooserPresenter?.cancelSelection()

        let chooserPresenter = TargetChooserPopoverPresenter(
            urlString: urlString,
            options: options,
            footerWarning: footerWarning
        )
        self.chooserPresenter = chooserPresenter

        let action = await chooserPresenter.selectTarget(relativeTo: anchorView)
        if self.chooserPresenter === chooserPresenter {
            self.chooserPresenter = nil
        }
        return action
    }

    func refocusChooser() {
        chooserPresenter?.refocus()
    }
}

/// Adapts runner notifications to menu-bar logging and transient toast UI.
@MainActor
final class MenuBarNotifier: QRGoNotifying {
    let reportsDeviceOpenResults = true
    /// Status item button used as the popover anchor; owned by the status item.
    weak var anchorView: NSView?

    private let toastPresenter = MenuBarToastPresenter()

    func error(_ message: String) {
        QRGoLogger.menuBarError(message)
        toastPresenter.show(message: message, style: .failure, relativeTo: anchorView)
    }

    func info(_ message: String) {
        QRGoLogger.menuBarInfo(message)
    }

    func success(_ message: String) {
        QRGoLogger.menuBarInfo(message)
        toastPresenter.show(message: message, style: .success, relativeTo: anchorView)
    }

    func warning(_ message: String) {
        QRGoLogger.menuBarWarning(message)
        toastPresenter.show(message: message, style: .warning, relativeTo: anchorView)
    }

    func updateAvailable(_ update: MenuBarUpdate, installAction: @escaping () -> Void) {
        QRGoLogger.menuBarInfo("Showing QRGo update prompt for \(update.currentVersion).")
        toastPresenter.show(
            message: "QRGo update available",
            style: .info,
            relativeTo: anchorView,
            actions: [
                MenuBarToastAction(title: "Later", handler: {}),
                MenuBarToastAction(title: "Install", handler: installAction)
            ]
        )
    }

    func dismissVisibleToast() {
        toastPresenter.dismiss()
    }
}
