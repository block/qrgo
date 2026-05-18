import AppKit

/// Computes the chooser's fixed popover size and scrollable button viewport.
///
/// The URL and footer stay fixed while large target lists scroll inside the button area, keeping the anchored popover
/// from growing off-screen.
struct TargetChooserLayout {
    static let width: CGFloat = 440
    static let maxHeight: CGFloat = 520
    static let horizontalPadding: CGFloat = 24
    static let headingTopPadding: CGFloat = 16
    static let headingHeight: CGFloat = 22
    static let headingUrlSpacing: CGFloat = 8
    static let urlHeight: CGFloat = 48
    static let urlButtonSpacing: CGFloat = 12
    static let buttonHeight: CGFloat = 36
    static let buttonSpacing: CGFloat = 12
    static let buttonSymbolPointSize: CGFloat = 18
    static let buttonTitlePointSize: CGFloat = NSFont.systemFontSize
    static let footerTopSpacing: CGFloat = 14
    static let footerHeight: CGFloat = 34
    static let bottomPadding: CGFloat = 20

    let contentSize: NSSize
    let buttonViewportHeight: CGFloat
    let buttonStackHeight: CGFloat
    let requiresScrolling: Bool

    init(optionCount: Int, hasFooter: Bool) {
        buttonStackHeight = Self.buttonStackHeight(optionCount: optionCount)
        let fixedHeight = Self.fixedHeight(hasFooter: hasFooter)
        let fullHeight = fixedHeight + buttonStackHeight
        let height = min(fullHeight, Self.maxHeight)

        contentSize = NSSize(width: Self.width, height: height)
        buttonViewportHeight = buttonStackHeight == 0 ? 0 : max(Self.buttonHeight, height - fixedHeight)
        requiresScrolling = buttonStackHeight > buttonViewportHeight
    }

    static func buttonStackHeight(optionCount: Int) -> CGFloat {
        let buttonCount = CGFloat(max(0, optionCount))
        let spacingCount = CGFloat(max(0, optionCount - 1))
        return buttonCount * buttonHeight + spacingCount * buttonSpacing
    }

    private static func fixedHeight(hasFooter: Bool) -> CGFloat {
        let footerAreaHeight = hasFooter ? footerTopSpacing + footerHeight : 0
        return headingTopPadding +
            headingHeight +
            headingUrlSpacing +
            urlHeight +
            urlButtonSpacing +
            footerAreaHeight +
            bottomPadding
    }
}

/// Presents a persistent target chooser popover anchored to the menu-bar status item.
///
/// Unlike notification toasts, this presenter has no dismissal timer and completes its async selection only after a row
/// is chosen, Escape is pressed, the task is canceled, or AppKit closes the popover unexpectedly.
@MainActor
final class TargetChooserPopoverPresenter: NSObject, NSPopoverDelegate {
    private let urlString: String
    private let options: [TargetOption]
    private let footerWarning: String?

    private var popover: NSPopover?
    private var viewController: TargetChooserViewController?
    private var continuation: CheckedContinuation<TargetAction?, Never>?
    private var localEventMonitor: Any?
    private var terminationObserver: Any?

    var isShowing: Bool {
        popover?.isShown == true
    }

    init(urlString: String, options: [TargetOption], footerWarning: String? = nil) {
        self.urlString = urlString
        self.options = options
        self.footerWarning = footerWarning
        super.init()
    }

    deinit {
        if let localEventMonitor = localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
        if let terminationObserver = terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
        continuation?.resume(returning: nil)
    }

    func selectTarget(relativeTo anchorView: NSView) async -> TargetAction? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                present(relativeTo: anchorView, continuation: continuation)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelSelection()
            }
        }
    }

    func cancelSelection() {
        completeSelection(with: nil)
    }

    func refocus() {
        NSApp.activate(ignoringOtherApps: true)
        popover?.contentViewController?.view.window?.makeKey()
        viewController?.focusFirstChoice()
    }

    func popoverDidClose(_ notification: Notification) {
        completeSelection(with: nil, shouldClosePopover: false)
    }

    private func present(
        relativeTo anchorView: NSView,
        continuation: CheckedContinuation<TargetAction?, Never>
    ) {
        guard self.continuation == nil else {
            continuation.resume(returning: nil)
            return
        }
        guard anchorView.window != nil else {
            NSSound.beep()
            continuation.resume(returning: nil)
            return
        }

        let viewController = TargetChooserViewController(
            urlString: urlString,
            options: options,
            footerWarning: footerWarning
        )
        viewController.onSelect = { [weak self] action in
            self?.completeSelection(with: action)
        }
        viewController.onCancel = { [weak self] in
            self?.completeSelection(with: nil)
        }

        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self
        popover.contentSize = viewController.contentSize
        popover.contentViewController = viewController

        self.continuation = continuation
        self.viewController = viewController
        self.popover = popover
        installCancellationObservers()

        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
        DispatchQueue.main.async { [weak self] in
            self?.refocus()
        }
    }

    private func completeSelection(with action: TargetAction?, shouldClosePopover: Bool = true) {
        guard let continuation = continuation else {
            return
        }

        let popover = popover
        removeCancellationObservers()
        self.continuation = nil
        self.viewController = nil
        self.popover = nil

        popover?.delegate = nil
        if shouldClosePopover {
            popover?.close()
        }
        continuation.resume(returning: action)
    }

    private func installCancellationObservers() {
        // The popover does not reliably advance focus through these custom-drawn buttons with AppKit's default key-view
        // loop, so keyboard navigation and Return/Enter selection are handled explicitly here.
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 48 || event.keyCode == 125 || event.keyCode == 126 {
                let movesBackward = event.keyCode == 126 ||
                    (event.keyCode == 48 && event.modifierFlags.contains(.shift))
                Task { @MainActor [weak self] in
                    self?.viewController?.focusAdjacentChoice(backward: movesBackward)
                }
                return nil
            }
            if event.keyCode == 36 || event.keyCode == 76 {
                Task { @MainActor [weak self] in
                    self?.viewController?.selectFocusedChoice()
                }
                return nil
            }
            guard event.keyCode == 53 || event.charactersIgnoringModifiers == "\u{1b}" else {
                return event
            }
            Task { @MainActor [weak self] in
                self?.cancelSelection()
            }
            return nil
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cancelSelection()
            }
        }
    }

    private func removeCancellationObservers() {
        if let localEventMonitor = localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let terminationObserver = terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
            self.terminationObserver = nil
        }
    }
}

@MainActor
private final class TargetChooserViewController: NSViewController {
    var onSelect: ((TargetAction) -> Void)?
    var onCancel: (() -> Void)?

    let contentSize: NSSize

    private let urlString: String
    private let options: [TargetOption]
    private let footerWarning: String?
    private let layout: TargetChooserLayout
    private var choiceButtons: [NSButton] = []
    private var isSelectingTarget = false

    init(urlString: String, options: [TargetOption], footerWarning: String?) {
        self.urlString = urlString
        self.options = options
        self.footerWarning = footerWarning
        layout = TargetChooserLayout(optionCount: options.count, hasFooter: footerWarning != nil)
        contentSize = layout.contentSize
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = contentSize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let container = makeContainer()
        let headingLabel = makeHeadingLabel()
        let urlLabel = makeURLLabel()
        let buttonViews = makeButtonScrollViews()
        let footerLabel = makeFooterLabel()

        container.addSubview(headingLabel)
        container.addSubview(urlLabel)
        container.addSubview(buttonViews.scrollView)
        if let footerLabel = footerLabel {
            container.addSubview(footerLabel)
        }

        activateBaseConstraints(
            container: container,
            headingLabel: headingLabel,
            urlLabel: urlLabel,
            buttonViews: buttonViews
        )
        activateFooterConstraints(
            container: container,
            scrollView: buttonViews.scrollView,
            footerLabel: footerLabel
        )

        view = container
    }
}

extension TargetChooserViewController {
    private func makeContainer() -> TargetChooserRootView {
        let container = TargetChooserRootView(frame: NSRect(origin: .zero, size: contentSize))
        container.material = .popover
        container.blendingMode = .behindWindow
        container.state = .active
        container.onCancel = { [weak self] in
            self?.onCancel?()
        }
        return container
    }

    private func makeHeadingLabel() -> NSTextField {
        let headingLabel = NSTextField(labelWithString: "Open QR Code")
        headingLabel.translatesAutoresizingMaskIntoConstraints = false
        headingLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        headingLabel.textColor = .labelColor
        headingLabel.setAccessibilityLabel("Open QR Code")
        return headingLabel
    }

    private func makeURLLabel() -> NSTextField {
        let urlLabel = NSTextField(wrappingLabelWithString: urlString)
        urlLabel.translatesAutoresizingMaskIntoConstraints = false
        urlLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        urlLabel.textColor = .secondaryLabelColor
        urlLabel.lineBreakMode = .byCharWrapping
        urlLabel.preferredMaxLayoutWidth = contentSize.width - (TargetChooserLayout.horizontalPadding * 2)
        urlLabel.maximumNumberOfLines = 3
        urlLabel.usesSingleLineMode = false
        urlLabel.cell?.lineBreakMode = .byCharWrapping
        urlLabel.cell?.wraps = true
        urlLabel.cell?.isScrollable = false
        urlLabel.setAccessibilityLabel("QR code URL")
        urlLabel.setAccessibilityValue(urlString)
        return urlLabel
    }

    private func makeButtonScrollViews() -> TargetChooserButtonViews {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = layout.requiresScrolling
        scrollView.autohidesScrollers = true

        let buttonDocumentView = NSView()
        buttonDocumentView.translatesAutoresizingMaskIntoConstraints = false

        let buttonStack = NSStackView()
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.orientation = .vertical
        buttonStack.alignment = .width
        buttonStack.spacing = TargetChooserLayout.buttonSpacing

        choiceButtons = []
        for (index, option) in options.enumerated() {
            let button = makeChoiceButton(for: option, index: index)
            choiceButtons.append(button)
            buttonStack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: buttonStack.widthAnchor).isActive = true
        }

        buttonDocumentView.addSubview(buttonStack)
        scrollView.documentView = buttonDocumentView
        return TargetChooserButtonViews(
            scrollView: scrollView,
            documentView: buttonDocumentView,
            stack: buttonStack
        )
    }

    private func makeFooterLabel() -> NSTextField? {
        guard let footerWarning = footerWarning else {
            return nil
        }

        let label = NSTextField(wrappingLabelWithString: footerWarning)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 2
        label.textColor = .secondaryLabelColor
        label.setAccessibilityLabel(footerWarning)
        return label
    }

    private func activateBaseConstraints(
        container: NSView,
        headingLabel: NSTextField,
        urlLabel: NSTextField,
        buttonViews: TargetChooserButtonViews
    ) {
        let scrollView = buttonViews.scrollView
        let buttonDocumentView = buttonViews.documentView
        let buttonStack = buttonViews.stack

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: contentSize.width),
            container.heightAnchor.constraint(equalToConstant: contentSize.height),

            headingLabel.leadingAnchor.constraint(
                equalTo: container.leadingAnchor,
                constant: TargetChooserLayout.horizontalPadding
            ),
            headingLabel.trailingAnchor.constraint(
                equalTo: container.trailingAnchor,
                constant: -TargetChooserLayout.horizontalPadding
            ),
            headingLabel.topAnchor.constraint(
                equalTo: container.topAnchor,
                constant: TargetChooserLayout.headingTopPadding
            ),
            headingLabel.heightAnchor.constraint(equalToConstant: TargetChooserLayout.headingHeight),

            urlLabel.leadingAnchor.constraint(
                equalTo: container.leadingAnchor,
                constant: TargetChooserLayout.horizontalPadding
            ),
            urlLabel.trailingAnchor.constraint(
                equalTo: container.trailingAnchor,
                constant: -TargetChooserLayout.horizontalPadding
            ),
            urlLabel.topAnchor.constraint(
                equalTo: headingLabel.bottomAnchor,
                constant: TargetChooserLayout.headingUrlSpacing
            ),
            urlLabel.heightAnchor.constraint(equalToConstant: TargetChooserLayout.urlHeight),

            scrollView.leadingAnchor.constraint(
                equalTo: container.leadingAnchor,
                constant: TargetChooserLayout.horizontalPadding
            ),
            scrollView.trailingAnchor.constraint(
                equalTo: container.trailingAnchor,
                constant: -TargetChooserLayout.horizontalPadding
            ),
            scrollView.topAnchor.constraint(
                equalTo: urlLabel.bottomAnchor,
                constant: TargetChooserLayout.urlButtonSpacing
            ),
            scrollView.heightAnchor.constraint(equalToConstant: layout.buttonViewportHeight),

            buttonDocumentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            buttonDocumentView.heightAnchor.constraint(equalToConstant: layout.buttonStackHeight),

            buttonStack.leadingAnchor.constraint(equalTo: buttonDocumentView.leadingAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: buttonDocumentView.trailingAnchor),
            buttonStack.topAnchor.constraint(equalTo: buttonDocumentView.topAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: buttonDocumentView.bottomAnchor)
        ])
    }

    private func activateFooterConstraints(
        container: NSView,
        scrollView: NSScrollView,
        footerLabel: NSTextField?
    ) {
        if let footerLabel = footerLabel {
            NSLayoutConstraint.activate([
                footerLabel.leadingAnchor.constraint(
                    equalTo: container.leadingAnchor,
                    constant: TargetChooserLayout.horizontalPadding
                ),
                footerLabel.trailingAnchor.constraint(
                    equalTo: container.trailingAnchor,
                    constant: -TargetChooserLayout.horizontalPadding
                ),
                footerLabel.topAnchor.constraint(
                    equalTo: scrollView.bottomAnchor,
                    constant: TargetChooserLayout.footerTopSpacing
                ),
                footerLabel.bottomAnchor.constraint(
                    equalTo: container.bottomAnchor,
                    constant: -TargetChooserLayout.bottomPadding
                ),
                footerLabel.heightAnchor.constraint(equalToConstant: TargetChooserLayout.footerHeight)
            ])
        } else {
            scrollView.bottomAnchor.constraint(
                equalTo: container.bottomAnchor,
                constant: -TargetChooserLayout.bottomPadding
            ).isActive = true
        }
    }

    func focusFirstChoice() {
        view.window?.makeKey()
        if let firstChoiceButton = choiceButtons.first {
            view.window?.makeFirstResponder(firstChoiceButton)
            firstChoiceButton.scrollToVisible(firstChoiceButton.bounds)
        } else {
            view.window?.makeFirstResponder(view)
        }
    }

    func focusAdjacentChoice(backward: Bool) {
        guard !choiceButtons.isEmpty else {
            view.window?.makeFirstResponder(view)
            return
        }

        let currentButton = view.window?.firstResponder as? NSButton
        let currentIndex = currentButton.flatMap { button in
            choiceButtons.firstIndex { $0 === button }
        }
        let fallbackIndex = backward ? 0 : choiceButtons.count - 1
        let nextIndex = ((currentIndex ?? fallbackIndex) + (backward ? -1 : 1) + choiceButtons.count) %
            choiceButtons.count
        let nextButton = choiceButtons[nextIndex]
        view.window?.makeFirstResponder(nextButton)
        nextButton.scrollToVisible(nextButton.bounds)
    }

    func selectFocusedChoice() {
        guard let focusedButton = view.window?.firstResponder as? NSButton,
              choiceButtons.contains(where: { $0 === focusedButton }),
              focusedButton.isEnabled else {
            return
        }
        focusedButton.performClick(nil)
    }

    private func makeChoiceButton(for option: TargetOption, index: Int) -> NSButton {
        let button = TargetChoiceButton(
            option: displayOption(for: option),
            titlePointSize: TargetChooserLayout.buttonTitlePointSize,
            symbolPointSize: TargetChooserLayout.buttonSymbolPointSize
        )
        button.target = self
        button.action = #selector(selectTarget(_:))
        button.tag = index

        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: TargetChooserLayout.buttonHeight)
        ])

        return button
    }

    private func displayOption(for option: TargetOption) -> TargetOption {
        guard option.action == .skip else {
            return option
        }
        return TargetOption(
            displayName: "Cancel (Esc)",
            systemSymbolName: option.systemSymbolName,
            action: option.action
        )
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

private struct TargetChooserButtonViews {
    let scrollView: NSScrollView
    let documentView: NSView
    let stack: NSStackView
}
