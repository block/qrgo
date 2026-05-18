import AppKit

struct MenuBarToastAction {
    let title: String
    let handler: () -> Void
}

enum MenuBarToastStyle {
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

/// Owns the visible toast popover and replaces it when a newer notification arrives.
@MainActor
final class MenuBarToastPresenter: NSObject, NSPopoverDelegate {
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

    func dismiss() {
        dismissalWorkItem?.cancel()
        dismissalWorkItem = nil
        popover?.delegate = nil
        popover?.close()
        popover = nil
    }

    func popoverDidClose(_ notification: Notification) {
        dismissalWorkItem?.cancel()
        dismissalWorkItem = nil
        popover = nil
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
