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
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            startScan()
        }
    }

    @objc private func startScan() {
        guard !isRunningAction else {
            notifier.warning("QRGo is already busy.")
            return
        }

        QRGoLogger.menuBarInfo("Starting QR scan from menu bar.")
        isRunningAction = true
        Task { @MainActor in
            let runner = QRGoRunner(
                configuration: configuration,
                targetSelector: AppKitTargetSelector(),
                notifier: notifier
            )
            _ = await runner.run()
            isRunningAction = false
        }
    }

    @objc private func openLastScan() {
        guard !isRunningAction else {
            notifier.warning("QRGo is already busy.")
            return
        }

        QRGoLogger.menuBarInfo("Opening last scanned QR code from menu bar.")
        isRunningAction = true
        Task { @MainActor in
            let runner = QRGoRunner(
                configuration: configuration,
                targetSelector: AppKitTargetSelector(),
                notifier: notifier
            )
            _ = await runner.openLastScan()
            isRunningAction = false
        }
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = MenuBarSettingsWindowController { [weak self] in
                self?.registeredShortcut
            }
        }
        settingsWindowController?.showWindow(nil)
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
        scanItem.isEnabled = !isRunningAction
        menu.addItem(scanItem)

        let openLastItem = NSMenuItem(title: "Open Last QR Code", action: #selector(openLastScan), keyEquivalent: "")
        openLastItem.isEnabled = LastScanStore.hasLastScan && !isRunningAction
        menu.addItem(openLastItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.image = nil
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit QRGo", action: #selector(quit), keyEquivalent: "q"))
        menu.delegate = self

        for item in menu.items {
            item.target = self
        }

        // Attach the menu only while AppKit is tracking this click so normal left-clicks keep scanning.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
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
    func selectTarget(for urlString: String, from options: [TargetOption]) -> TargetAction? {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Open QR Code"
        alert.informativeText = urlString
        alert.alertStyle = .informational

        for option in options {
            alert.addButton(withTitle: option.displayName)
        }

        let response = alert.runModal()
        let selectedIndex = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard selectedIndex >= 0 && selectedIndex < options.count else {
            return nil
        }
        return options[selectedIndex].action
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
}

/// Owns the visible toast popover and replaces it when a newer notification arrives.
@MainActor
private final class MenuBarToastPresenter: NSObject, NSPopoverDelegate {
    private var popover: NSPopover?
    private var dismissalWorkItem: DispatchWorkItem?

    func show(message: String, style: MenuBarToastStyle, relativeTo anchorView: NSView?) {
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
        popover.contentSize = MenuBarToastViewController.preferredSize
        popover.contentViewController = MenuBarToastViewController(message: message, style: style)

        self.popover = popover
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)

        let dismissalWorkItem = DispatchWorkItem { [weak self, weak popover] in
            popover?.close()
            if self?.popover === popover {
                self?.popover = nil
            }
        }
        self.dismissalWorkItem = dismissalWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: dismissalWorkItem)
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

    var iconName: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "xmark.octagon.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
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
        }
    }
}

/// Builds compact content for one menu-bar toast popover.
@MainActor
private final class MenuBarToastViewController: NSViewController {
    static let preferredSize = NSSize(width: 280, height: 40)

    private let message: String
    private let style: MenuBarToastStyle

    init(message: String, style: MenuBarToastStyle) {
        self.message = message
        self.style = style
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
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

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: Self.preferredSize.width),
            container.heightAnchor.constraint(equalToConstant: Self.preferredSize.height),

            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),

            messageLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            messageLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            messageLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        view = container
    }
}
