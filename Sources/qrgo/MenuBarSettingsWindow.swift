import AppKit

@MainActor
final class MenuBarSettingsWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: () -> Void

    init(
        registeredShortcutProvider: @escaping () -> KeyboardShortcut?,
        onClose: @escaping () -> Void = {}
    ) {
        self.onClose = onClose
        let viewController = MenuBarSettingsViewController(
            registeredShortcutProvider: registeredShortcutProvider
        )
        let window = NSWindow(contentViewController: viewController)
        window.title = "QRGo Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.contentMinSize = MenuBarSettingsViewController.contentSize
        window.contentMaxSize = MenuBarSettingsViewController.contentSize
        window.setContentSize(MenuBarSettingsViewController.contentSize)

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func showWindow(_ sender: Any?) {
        window?.setContentSize(MenuBarSettingsViewController.contentSize)
        window?.center()
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

@MainActor
private final class MenuBarSettingsViewController: NSViewController {
    static let contentSize = NSSize(width: 480, height: 150)

    private let registeredShortcutProvider: () -> KeyboardShortcut?
    private let shortcutButton = ShortcutRecorderButton()
    private let resetButton = NSButton(title: "Use Default", target: nil, action: nil)
    private let launchAtLoginSwitch = NSSwitch(frame: .zero)
    private let statusLabel = NSTextField(labelWithString: "")

    init(registeredShortcutProvider: @escaping () -> KeyboardShortcut?) {
        self.registeredShortcutProvider = registeredShortcutProvider
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = Self.contentSize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        let container = NSView(frame: NSRect(origin: .zero, size: Self.contentSize))

        let launchAtLoginLabel = makeSettingLabel("Launch at login")
        let shortcutLabel = makeSettingLabel("Scan QR shortcut")

        configureControls()

        container.addSubview(launchAtLoginLabel)
        container.addSubview(launchAtLoginSwitch)
        container.addSubview(shortcutLabel)
        container.addSubview(shortcutButton)
        container.addSubview(resetButton)
        container.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: Self.contentSize.width),
            container.heightAnchor.constraint(equalToConstant: Self.contentSize.height),

            launchAtLoginLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            launchAtLoginLabel.centerYAnchor.constraint(equalTo: launchAtLoginSwitch.centerYAnchor),

            launchAtLoginSwitch.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            launchAtLoginSwitch.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),

            shortcutLabel.leadingAnchor.constraint(equalTo: launchAtLoginLabel.leadingAnchor),
            shortcutLabel.centerYAnchor.constraint(equalTo: shortcutButton.centerYAnchor),
            shortcutLabel.trailingAnchor.constraint(lessThanOrEqualTo: shortcutButton.leadingAnchor, constant: -16),

            resetButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),

            shortcutButton.trailingAnchor.constraint(equalTo: resetButton.leadingAnchor, constant: -10),
            shortcutButton.topAnchor.constraint(equalTo: launchAtLoginSwitch.bottomAnchor, constant: 24),
            shortcutButton.widthAnchor.constraint(equalToConstant: 150),
            resetButton.centerYAnchor.constraint(equalTo: shortcutButton.centerYAnchor),

            statusLabel.leadingAnchor.constraint(equalTo: shortcutLabel.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            statusLabel.topAnchor.constraint(equalTo: shortcutButton.bottomAnchor, constant: 6)
        ])

        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        refreshShortcut()
        shortcutButton.onShortcutRecorded = { [weak self] shortcut in
            self?.saveShortcut(shortcut)
        }
        shortcutButton.onValidationError = { [weak self] message in
            self?.showValidationMessage(message)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shortcutDidChange),
            name: MenuBarSettingsStore.scanShortcutDidChange,
            object: nil
        )
    }

    @objc private func resetShortcut() {
        let shortcut = KeyboardShortcut.defaultScan
        if let message = KeyboardShortcutValidator.validationMessage(
            for: shortcut,
            currentShortcut: registeredShortcutProvider()
        ) {
            showValidationMessage(message)
            return
        }
        MenuBarSettingsStore.resetScanShortcut()
        refreshShortcut()
        clearStatusMessage()
    }

    @objc private func shortcutDidChange() {
        refreshShortcut()
    }

    private func saveShortcut(_ shortcut: KeyboardShortcut) {
        MenuBarSettingsStore.scanShortcut = shortcut
        refreshShortcut()
        clearStatusMessage()
    }

    private func refreshShortcut() {
        let shortcut = MenuBarSettingsStore.scanShortcut
        shortcutButton.currentShortcut = shortcut
        shortcutButton.currentRegisteredShortcut = registeredShortcutProvider()
        launchAtLoginSwitch.state = LoginItemHelper.isInstalled ? .on : .off
    }

    private func showValidationMessage(_ message: String) {
        statusLabel.textColor = .systemRed
        statusLabel.stringValue = message
    }

    private func clearStatusMessage() {
        statusLabel.stringValue = ""
    }

    private func configureControls() {
        shortcutButton.translatesAutoresizingMaskIntoConstraints = false
        shortcutButton.setAccessibilityLabel("Scan QR Code keyboard shortcut")
        shortcutButton.setAccessibilityHelp("Records the global keyboard shortcut used to scan a QR code.")

        resetButton.translatesAutoresizingMaskIntoConstraints = false
        resetButton.bezelStyle = .rounded
        resetButton.target = self
        resetButton.action = #selector(resetShortcut)
        resetButton.setAccessibilityHelp("Restores the default global scan shortcut.")

        launchAtLoginSwitch.translatesAutoresizingMaskIntoConstraints = false
        launchAtLoginSwitch.target = self
        launchAtLoginSwitch.action = #selector(toggleLaunchAtLogin)
        launchAtLoginSwitch.setAccessibilityLabel("Launch at login")
        launchAtLoginSwitch.setAccessibilityHelp("Starts QRGo automatically when you log in.")

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setAccessibilityLabel("Settings status")
    }

    private func makeSettingLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .left
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        label.textColor = .labelColor
        return label
    }

    @objc private func toggleLaunchAtLogin() {
        QRGoLogger.menuBarInfo("Toggling QRGo launch-at-login setting from settings.")

        let shouldInstall = launchAtLoginSwitch.state == .on
        let succeeded = shouldInstall ?
            LoginItemHelper.install(loadImmediately: false) :
            LoginItemHelper.uninstall()

        launchAtLoginSwitch.state = LoginItemHelper.isInstalled ? .on : .off
        if succeeded {
            clearStatusMessage()
        } else {
            statusLabel.textColor = .systemRed
            statusLabel.stringValue = "Could not update the launch-at-login setting."
        }
    }
}

@MainActor
private final class ShortcutRecorderButton: NSButton {
    var currentShortcut: KeyboardShortcut? {
        didSet {
            updateTitle()
        }
    }
    var currentRegisteredShortcut: KeyboardShortcut?
    var onShortcutRecorded: ((KeyboardShortcut) -> Void)?
    var onValidationError: ((String) -> Void)?

    private var isRecording = false

    override var acceptsFirstResponder: Bool {
        true
    }

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(startRecording)
        focusRingType = .default
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        handleShortcutEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else {
            return super.performKeyEquivalent(with: event)
        }
        handleShortcutEvent(event)
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        guard !isRecording else {
            return
        }
        super.flagsChanged(with: event)
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            finishRecording()
        }
        return super.resignFirstResponder()
    }

    @objc private func startRecording() {
        isRecording = true
        title = "Press Shortcut"
        window?.makeFirstResponder(self)
    }

    private func handleShortcutEvent(_ event: NSEvent) {
        if isCancelEvent(event) {
            finishRecording()
            return
        }

        guard let shortcut = KeyboardShortcut.from(event: event) else {
            showValidationMessage(KeyboardShortcutValidator.minimumModifierMessage)
            return
        }
        if let message = KeyboardShortcutValidator.validationMessage(
            for: shortcut,
            currentShortcut: currentRegisteredShortcut
        ) {
            showValidationMessage(message)
            return
        }

        finishRecording()
        currentShortcut = shortcut
        onShortcutRecorded?(shortcut)
    }

    private func isCancelEvent(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(KeyboardShortcut.allowedModifiers)
        return event.keyCode == KeyboardShortcutKeyCode.escape && modifiers.isEmpty
    }

    private func finishRecording() {
        isRecording = false
        updateTitle()
    }

    private func showValidationMessage(_ message: String) {
        NSSound.beep()
        onValidationError?(message)
    }

    private func updateTitle() {
        guard !isRecording else {
            return
        }
        let shortcutTitle = currentShortcut?.displayString
        title = shortcutTitle ?? "Record"
        setAccessibilityValue(shortcutTitle)
    }
}
