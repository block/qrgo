import AppKit

/// Modal update installer window shown after the user accepts an available QRGo update.
@MainActor
final class MenuBarUpdateInstallWindowController: NSWindowController, NSWindowDelegate {
    private let updateViewController: MenuBarUpdateInstallViewController
    private let onClose: () -> Void

    var isInstalling: Bool {
        updateViewController.isInstalling
    }

    init(
        update: MenuBarUpdate,
        installHandler: @escaping () async -> MenuBarUpdateInstallResult,
        onClose: @escaping () -> Void
    ) {
        updateViewController = MenuBarUpdateInstallViewController(
            update: update,
            installHandler: installHandler
        )
        self.onClose = onClose

        let window = NSWindow(contentViewController: updateViewController)
        window.title = "Install QRGo Update"
        MenuBarModalWindow.configure(window)
        window.contentMinSize = MenuBarUpdateInstallViewController.contentSize
        window.contentMaxSize = MenuBarUpdateInstallViewController.contentSize
        window.setContentSize(MenuBarUpdateInstallViewController.contentSize)

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func showWindow(_ sender: Any?) {
        guard let window = window else {
            return
        }
        window.setContentSize(MenuBarUpdateInstallViewController.contentSize)
        MenuBarModalWindow.show(window)
        updateViewController.startInstallIfNeeded()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        !updateViewController.isInstalling
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

@MainActor
private final class MenuBarUpdateInstallViewController: NSViewController {
    static let contentSize = NSSize(width: 440, height: 170)

    private let update: MenuBarUpdate
    private let installHandler: () async -> MenuBarUpdateInstallResult
    private let spinner = NSProgressIndicator()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let primaryButton = NSButton(title: "Retry", target: nil, action: nil)
    private let secondaryButton = NSButton(title: "Cancel", target: nil, action: nil)
    private var hasStartedInstall = false

    private(set) var isInstalling = false

    init(update: MenuBarUpdate, installHandler: @escaping () async -> MenuBarUpdateInstallResult) {
        self.update = update
        self.installHandler = installHandler
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = Self.contentSize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let container = NSView(frame: NSRect(origin: .zero, size: Self.contentSize))

        configureControls()

        container.addSubview(spinner)
        container.addSubview(titleLabel)
        container.addSubview(detailLabel)
        container.addSubview(primaryButton)
        container.addSubview(secondaryButton)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: Self.contentSize.width),
            container.heightAnchor.constraint(equalToConstant: Self.contentSize.height),

            spinner.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            spinner.topAnchor.constraint(equalTo: container.topAnchor, constant: 25),
            spinner.widthAnchor.constraint(equalToConstant: 24),
            spinner.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 22),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),

            secondaryButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            secondaryButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),

            primaryButton.trailingAnchor.constraint(equalTo: secondaryButton.leadingAnchor, constant: -10),
            primaryButton.centerYAnchor.constraint(equalTo: secondaryButton.centerYAnchor)
        ])

        view = container
    }

    func startInstallIfNeeded() {
        guard !hasStartedInstall else {
            return
        }
        hasStartedInstall = true
        startInstall()
    }

    @objc private func retryInstall() {
        startInstall()
    }

    @objc private func closeWindow() {
        view.window?.close()
    }

    @objc private func restartQRGo() {
        if !MenuBarRelaunchHelper.relaunchAfterTermination() {
            titleLabel.stringValue = "Could not restart QRGo"
            detailLabel.stringValue = "Quit and reopen QRGo to use version \(update.currentVersion)."
            primaryButton.title = "Quit QRGo"
            primaryButton.action = #selector(quitQRGo)
        }
    }

    @objc private func quitQRGo() {
        NSApp.terminate(nil)
    }

    private func startInstall() {
        guard !isInstalling else {
            return
        }

        isInstalling = true
        showInstallingState()

        Task { [weak self] in
            guard let self = self else { return }
            let result = await self.installHandler()
            self.isInstalling = false

            switch result {
            case .installed:
                self.showSuccessState()
            case .failed(let error):
                QRGoLogger.menuBarError("QRGo update install failed: \(error.message) \(error.details)")
                self.showFailureState(error)
            }
        }
    }

    private func showInstallingState() {
        titleLabel.stringValue = "Installing QRGo \(update.currentVersion)"
        detailLabel.stringValue = "Homebrew is upgrading the QRGo app. This can take a few minutes."
        spinner.isHidden = false
        spinner.startAnimation(nil)
        primaryButton.isHidden = true
        secondaryButton.isHidden = true
    }

    private func showSuccessState() {
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        titleLabel.stringValue = "Update installed"
        // Homebrew replaces the app bundle, but the currently running process is still the old binary.
        detailLabel.stringValue = "Restart QRGo to use version \(update.currentVersion)."
        primaryButton.title = "Restart QRGo"
        primaryButton.action = #selector(restartQRGo)
        primaryButton.isHidden = false
        secondaryButton.title = "Later"
        secondaryButton.isHidden = false
    }

    private func showFailureState(_ error: MenuBarUpdateCommandError) {
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        titleLabel.stringValue = "Could not install update"
        detailLabel.stringValue = error.message
        primaryButton.title = "Retry"
        primaryButton.action = #selector(retryInstall)
        primaryButton.isHidden = false
        secondaryButton.title = "Cancel"
        secondaryButton.isHidden = false
    }

    private func configureControls() {
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.isIndeterminate = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        titleLabel.textColor = .labelColor

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 3

        primaryButton.translatesAutoresizingMaskIntoConstraints = false
        primaryButton.bezelStyle = .rounded
        primaryButton.target = self

        secondaryButton.translatesAutoresizingMaskIntoConstraints = false
        secondaryButton.bezelStyle = .rounded
        secondaryButton.target = self
        secondaryButton.action = #selector(closeWindow)
    }
}
