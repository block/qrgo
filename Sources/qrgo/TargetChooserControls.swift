import AppKit

/// Custom row button used by the target chooser.
///
/// AppKit's default focus ring can land around the SF Symbol image inside an image-leading `NSButton`; this class
/// suppresses that ring and draws focus around the whole row instead.
@MainActor
final class TargetChoiceButton: NSButton {
    private static let iconTitleSpacing: CGFloat = 8

    override var isEnabled: Bool {
        didSet {
            alphaValue = isEnabled ? 1 : 0.45
            needsDisplay = true
        }
    }

    override var acceptsFirstResponder: Bool {
        true
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
        focusRingType = .none
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
        drawFocusRingIfNeeded()
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        needsDisplay = true
    }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
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

    private func drawFocusRingIfNeeded() {
        guard window?.firstResponder === self else {
            return
        }

        NSColor.keyboardFocusIndicatorColor.setStroke()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 7, yRadius: 7)
        path.lineWidth = 3
        path.stroke()
    }
}

final class TargetChooserRootView: NSVisualEffectView {
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 || event.charactersIgnoringModifiers == "\u{1b}" {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }
}

private extension NSAppearance {
    var isDarkMode: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
