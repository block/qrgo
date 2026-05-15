import AppKit

@MainActor
final class TargetChooserWindowController: NSWindowController, NSWindowDelegate {
    private var selectedAction: TargetAction?

    init(urlString: String, options: [TargetOption]) {
        let viewController = TargetChooserViewController(urlString: urlString, options: options)
        let window = NSWindow(contentViewController: viewController)
        window.title = "Open QR Code"
        window.styleMask = [.titled, .closable]
        window.isMovable = true
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.level = .modalPanel
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.contentMinSize = viewController.contentSize
        window.contentMaxSize = viewController.contentSize
        window.setContentSize(viewController.contentSize)

        super.init(window: window)

        window.delegate = self
        viewController.onSelect = { [weak self] action in
            self?.finish(with: action)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func showModal() -> TargetAction? {
        guard let window = window else {
            return nil
        }

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: window)
        window.orderOut(nil)
        return selectedAction
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.stopModal()
    }

    private func finish(with action: TargetAction) {
        selectedAction = action
        NSApp.stopModal()
        window?.orderOut(nil)
    }
}

@MainActor
private final class TargetChooserViewController: NSViewController {
    var onSelect: ((TargetAction) -> Void)?

    let contentSize: NSSize

    private static let buttonHeight: CGFloat = 36
    private static let buttonSpacing: CGFloat = 12
    private static let buttonSymbolPointSize: CGFloat = 18
    private static let buttonTitlePointSize: CGFloat = NSFont.systemFontSize
    private static let horizontalPadding: CGFloat = 24
    private static let urlHeight: CGFloat = 48
    private static let urlTopPadding: CGFloat = 16
    private static let urlButtonSpacing: CGFloat = 6
    private static let bottomPadding: CGFloat = 24

    private let urlString: String
    private let options: [TargetOption]
    private var choiceButtons: [NSButton] = []
    private var isSelectingTarget = false

    init(urlString: String, options: [TargetOption]) {
        self.urlString = urlString
        self.options = options
        contentSize = Self.makeContentSize(optionCount: options.count)
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = contentSize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let container = NSView(frame: NSRect(origin: .zero, size: contentSize))

        let urlLabel = NSTextField(wrappingLabelWithString: urlString)
        urlLabel.translatesAutoresizingMaskIntoConstraints = false
        urlLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        urlLabel.textColor = .secondaryLabelColor
        urlLabel.lineBreakMode = .byCharWrapping
        urlLabel.preferredMaxLayoutWidth = contentSize.width - (Self.horizontalPadding * 2)
        urlLabel.maximumNumberOfLines = 3
        urlLabel.usesSingleLineMode = false
        urlLabel.cell?.lineBreakMode = .byCharWrapping
        urlLabel.cell?.wraps = true
        urlLabel.cell?.isScrollable = false
        urlLabel.setAccessibilityLabel("QR code URL")

        let buttonStack = NSStackView()
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.orientation = .vertical
        buttonStack.alignment = .width
        buttonStack.spacing = Self.buttonSpacing

        choiceButtons = []
        for (index, option) in options.enumerated() {
            let button = makeChoiceButton(for: option, index: index)
            choiceButtons.append(button)
            buttonStack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: buttonStack.widthAnchor).isActive = true
        }

        container.addSubview(urlLabel)
        container.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: contentSize.width),
            container.heightAnchor.constraint(equalToConstant: contentSize.height),

            urlLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.horizontalPadding),
            urlLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.horizontalPadding),
            urlLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: Self.urlTopPadding),
            urlLabel.heightAnchor.constraint(equalToConstant: Self.urlHeight),

            buttonStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.horizontalPadding),
            buttonStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.horizontalPadding),
            buttonStack.topAnchor.constraint(equalTo: urlLabel.bottomAnchor, constant: Self.urlButtonSpacing),
            buttonStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Self.bottomPadding)
        ])

        view = container
    }

    private static func makeContentSize(optionCount: Int) -> NSSize {
        let verticalPadding = urlTopPadding + urlHeight + urlButtonSpacing + bottomPadding
        let buttonStackHeight = CGFloat(optionCount) * buttonHeight + CGFloat(max(0, optionCount - 1)) * buttonSpacing
        return NSSize(width: 440, height: verticalPadding + buttonStackHeight)
    }

    private func makeChoiceButton(for option: TargetOption, index: Int) -> NSButton {
        let button = TargetChoiceButton(
            option: option,
            titlePointSize: Self.buttonTitlePointSize,
            symbolPointSize: Self.buttonSymbolPointSize
        )
        button.target = self
        button.action = #selector(selectTarget(_:))
        button.tag = index

        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: Self.buttonHeight)
        ])

        return button
    }

    @objc private func selectTarget(_ sender: NSButton) {
        guard !isSelectingTarget,
              sender.tag >= 0 && sender.tag < options.count else {
            return
        }
        isSelectingTarget = true
        disableChoiceButtons()

        let option = options[sender.tag]
        QRGoLogger.menuBarInfo("Selected target \(option.displayName).")
        onSelect?(option.action)
    }

    private func disableChoiceButtons() {
        for button in choiceButtons {
            button.isEnabled = false
            button.needsDisplay = true
        }
        view.window?.display()
    }
}

@MainActor
private final class TargetChoiceButton: NSButton {
    private static let iconTitleSpacing: CGFloat = 8

    override var isEnabled: Bool {
        didSet {
            alphaValue = isEnabled ? 1 : 0.45
            needsDisplay = true
        }
    }

    init(option: TargetOption, titlePointSize: CGFloat, symbolPointSize: CGFloat) {
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        alignment = .center
        attributedTitle = Self.makeTitle(option.displayName, pointSize: titlePointSize)
        attributedAlternateTitle = attributedTitle
        contentTintColor = .white
        controlSize = .large
        if let symbolImage = NSImage(systemSymbolName: option.systemSymbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .semibold)) {
            image = Self.image(symbolImage, trailingPadding: Self.iconTitleSpacing)
        }
        imageHugsTitle = true
        imagePosition = .imageLeading
        imageScaling = .scaleProportionallyDown
        isBordered = false
        lineBreakMode = .byTruncatingTail
        setAccessibilityLabel(option.displayName)
        setButtonType(.momentaryPushIn)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        let fillColor = cell?.isHighlighted == true ? pressedBackgroundColor : backgroundColor
        fillColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        super.draw(dirtyRect)
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        needsDisplay = true
    }

    private static func makeTitle(_ title: String, pointSize: CGFloat) -> NSAttributedString {
        NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: pointSize, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
        )
    }

    private static func image(_ image: NSImage, trailingPadding: CGFloat) -> NSImage {
        let paddedImage = NSImage(size: NSSize(
            width: image.size.width + trailingPadding,
            height: image.size.height
        ))
        paddedImage.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: image.size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        paddedImage.unlockFocus()
        paddedImage.isTemplate = true
        return paddedImage
    }

    private var backgroundColor: NSColor {
        if effectiveAppearance.isDarkMode {
            return NSColor.white.withAlphaComponent(0.10)
        }
        return NSColor(calibratedWhite: 0.26, alpha: 1)
    }

    private var pressedBackgroundColor: NSColor {
        if effectiveAppearance.isDarkMode {
            return NSColor.controlAccentColor.withAlphaComponent(0.32)
        }
        return .controlAccentColor
    }
}

private extension NSAppearance {
    var isDarkMode: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
