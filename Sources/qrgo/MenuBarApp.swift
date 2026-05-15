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
        }
        self.statusItem = statusItem
        applyScanShortcut()
        installUpdateCoordinator()
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
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
            let runner = QRGoRunner(
                configuration: configuration,
                targetSelector: AppKitTargetSelector(),
                notifier: notifier
            )
            _ = await runner.run()
            isRunningAction = false
            updateCoordinator?.idleStateDidChange()
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
            let runner = QRGoRunner(
                configuration: configuration,
                targetSelector: AppKitTargetSelector(),
                notifier: notifier
            )
            _ = await runner.openLastScan()
            isRunningAction = false
            updateCoordinator?.idleStateDidChange()
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
        settingsItem.isEnabled = updateInstallWindowController?.window?.isVisible != true
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

@MainActor
final class AppKitTargetSelector: QRGoTargetSelecting {
    func selectTarget(for urlString: String, from options: [TargetOption], footerWarning: String?) -> TargetAction? {
        NSApp.activate(ignoringOtherApps: true)
        let chooser = TargetChooserWindowController(
            urlString: urlString,
            options: options,
            footerWarning: footerWarning
        )
        return chooser.showModal()
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
}

private struct MenuBarToastAction {
    let title: String
    let handler: () -> Void
}

/// Owns the visible toast popover and replaces it when a newer notification arrives.
@MainActor
private final class MenuBarToastPresenter: NSObject, NSPopoverDelegate {
    private var popover: NSPopover?
    private var dismissalWorkItem: DispatchWorkItem?

    func show(
        message: String,
        style: MenuBarToastStyle,
        relativeTo anchorView: NSView?,
        actions: [MenuBarToastAction] = []
    ) {
        guard let anchorView = anchorView else {
            NSSound.beep()
            return
        }

        dismissalWorkItem?.cancel()
        // Closing a replaced popover should not run stale delegate cleanup.
        popover?.delegate = nil
        popover?.close()

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = MenuBarToastViewController.preferredSize(actionCount: actions.count)
        popover.contentViewController = MenuBarToastViewController(
            message: message,
            style: style,
            actions: actions
        )

        self.popover = popover
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)

        if actions.isEmpty {
            let dismissalWorkItem = DispatchWorkItem { [weak self, weak popover] in
                popover?.close()
                if self?.popover === popover {
                    self?.popover = nil
                }
            }
            self.dismissalWorkItem = dismissalWorkItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: dismissalWorkItem)
        } else {
            dismissalWorkItem = nil
        }
    }

    func popoverDidClose(_ notification: Notification) {
        dismissalWorkItem?.cancel()
        dismissalWorkItem = nil
        popover = nil
    }
}

private enum MenuBarToastStyle {
    case success
    case failure
    case warning
    case info

    var iconName: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "xmark.octagon.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .info:
            return "info.circle.fill"
        }
    }

    var iconColor: NSColor {
        switch self {
        case .success:
            return .systemGreen
        case .failure:
            return .systemRed
        case .warning:
            return .systemOrange
        case .info:
            return .systemBlue
        }
    }
}

/// Builds compact content for one menu-bar toast popover.
@MainActor
private final class MenuBarToastViewController: NSViewController {
    static func preferredSize(actionCount: Int) -> NSSize {
        let width: CGFloat = actionCount > 1 ? 410 : actionCount == 1 ? 360 : 280
        let height: CGFloat = actionCount > 0 ? 44 : 40
        return NSSize(width: width, height: height)
    }

    private let message: String
    private let style: MenuBarToastStyle
    private let actions: [MenuBarToastAction]

    init(message: String, style: MenuBarToastStyle, actions: [MenuBarToastAction]) {
        self.message = message
        self.style = style
        self.actions = actions
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let preferredSize = Self.preferredSize(actionCount: actions.count)
        let container = NSVisualEffectView()
        container.material = .popover
        container.blendingMode = .behindWindow
        container.state = .active

        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        iconView.image = NSImage(systemSymbolName: style.iconName, accessibilityDescription: nil)
        iconView.contentTintColor = style.iconColor

        let messageLabel = NSTextField(labelWithString: message)
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.maximumNumberOfLines = 2
        messageLabel.textColor = .labelColor

        container.addSubview(iconView)
        container.addSubview(messageLabel)

        var constraints = [
            container.widthAnchor.constraint(equalToConstant: preferredSize.width),
            container.heightAnchor.constraint(equalToConstant: preferredSize.height),

            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),

            messageLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            messageLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ]

        if !actions.isEmpty {
            let actionStack = NSStackView()
            actionStack.translatesAutoresizingMaskIntoConstraints = false
            actionStack.orientation = .horizontal
            actionStack.spacing = 6
            actionStack.alignment = .centerY
            container.addSubview(actionStack)

            for (index, action) in actions.enumerated() {
                let actionButton = NSButton(title: action.title, target: self, action: #selector(performAction(_:)))
                actionButton.translatesAutoresizingMaskIntoConstraints = false
                actionButton.bezelStyle = .rounded
                actionButton.tag = index
                actionStack.addArrangedSubview(actionButton)
            }

            constraints.append(contentsOf: [
                actionStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
                actionStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionStack.leadingAnchor, constant: -12)
            ])
        } else {
            constraints.append(messageLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8))
        }

        NSLayoutConstraint.activate(constraints)

        view = container
    }

    @objc private func performAction(_ sender: NSButton) {
        guard actions.indices.contains(sender.tag) else {
            return
        }
        view.window?.close()
        actions[sender.tag].handler()
    }
}
