import AppKit
import QuartzCore

/// Owns the temporary AppKit event loop needed when capture starts from the CLI.
@MainActor
final class SquareCaptureSelector: NSObject {
    private var panels: [SquareCapturePanel] = []
    private var eventMonitor: Any?
    private var selectedRect: CGRect?
    private var isSelecting = false

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func selectRegion() -> CGRect? {
        let app = NSApplication.shared
        let previousPolicy = app.activationPolicy()
        trace("Starting selection. Active: \(app.isActive), policy: \(previousPolicy.rawValue).")
        let screens = NSScreen.screens
        guard let primaryScreen = screens.first else { return nil }

        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        panels = screens.map { SquareCapturePanel(frame: $0.frame) }
        for panel in panels {
            panel.orderFrontRegardless()
        }
        let initialPanel = panels.first { $0.frame.contains(NSEvent.mouseLocation) } ?? panels[0]
        initialPanel.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        updateSelection()
        installEventMonitor()
        installCancellationObservers()
        NSCursor.hide()
        defer {
            isSelecting = false
            if let eventMonitor = eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
            }
            eventMonitor = nil
            panels.forEach { $0.orderOut(nil) }
            panels.removeAll()
            // Commit removal before screencapture starts so the outline cannot appear in the image.
            CATransaction.flush()
            NSCursor.unhide()
            app.setActivationPolicy(previousPolicy)
        }

        isSelecting = true
        let response = app.runModal(for: initialPanel)
        trace("Modal ended: \(response.rawValue), selected region: \(String(describing: selectedRect)).")
        guard response == .OK, let selectedRect = selectedRect else { return nil }
        return SquareCaptureGeometry.captureRect(selection: selectedRect, primaryScreenFrame: primaryScreen.frame)
    }

    private func installEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self = self, self.isSelecting else { return event }
            switch event.type {
            case .mouseMoved, .leftMouseDragged:
                self.updateSelection()
            case .leftMouseDown:
                self.trace("Received left click. Active: \(NSApp.isActive).")
                self.updateSelection()
                if self.selectedRect != nil {
                    self.finish(with: .OK)
                }
            case .rightMouseDown:
                self.trace("Received right click.")
                self.cancel()
            case .keyDown:
                if event.keyCode == 53 {
                    self.trace("Received Escape.")
                    self.cancel()
                }
            default:
                break
            }
            return nil
        }
    }

    private func installCancellationObservers() {
        for name in [NSApplication.didChangeScreenParametersNotification, NSApplication.didResignActiveNotification] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(cancelForNotification(_:)), name: name, object: nil
            )
        }
    }

    @objc private func cancelForNotification(_ notification: Notification) {
        trace("Cancellation notification: \(notification.name.rawValue), selecting: \(isSelecting).")
        cancel()
    }

    @objc private func cancel() {
        guard isSelecting else { return }
        selectedRect = nil
        finish(with: .cancel)
    }

    private func finish(with response: NSApplication.ModalResponse) {
        trace("Finishing with response: \(response.rawValue).")
        isSelecting = false
        NSApp.stopModal(withCode: response)
        // The monitor consumes the click or Escape event. Wake the modal loop so it can exit immediately.
        if let event = NSEvent.otherEvent(
            with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0
        ) {
            NSApp.postEvent(event, atStart: true)
        }
    }

    private func trace(_ message: String) {
        guard ProcessInfo.processInfo.environment["QRGO_CAPTURE_DEBUG"] == "1" else { return }
        fputs("QRGo capture: \(message)\n", stderr)
    }

    private func updateSelection() {
        let location = NSEvent.mouseLocation
        selectedRect = nil
        for panel in panels {
            guard let view = panel.contentView as? SquareCaptureView else { continue }
            if panel.frame.contains(location) {
                let rect = SquareCaptureGeometry.selectionRect(center: location, screenFrame: panel.frame)
                selectedRect = rect
                view.selectionRect = rect.offsetBy(dx: -panel.frame.minX, dy: -panel.frame.minY)
            } else {
                view.selectionRect = nil
            }
        }
    }
}

@MainActor
final class SquareCapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
        worksWhenModal = true
        hidesOnDeactivate = false
        sharingType = .none
        isReleasedWhenClosed = false
        contentView = SquareCaptureView(frame: CGRect(origin: .zero, size: frame.size))
    }
}

@MainActor
final class SquareCaptureView: NSView {
    var selectionRect: CGRect? {
        didSet { needsDisplay = true }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.08).setFill()
        dirtyRect.fill(using: .copy)
        guard let selectionRect = selectionRect else { return }

        // Fully transparent pixels pass clicks to the app underneath. Keep one alpha step
        // inside the square to receive clicks without visibly dimming the capture area.
        NSColor.black.withAlphaComponent(1.0 / 255.0).setFill()
        selectionRect.fill(using: .copy)

        let frame = selectionRect.insetBy(dx: 3, dy: 3)
        let cornerLength = min(32, frame.width * 0.15)
        let cornerRadius = min(10, cornerLength / 2)
        let corners = NSBezierPath()
        corners.lineCapStyle = .round
        corners.lineJoinStyle = .round
        for horizontal: CGFloat in [-1, 1] {
            for vertical: CGFloat in [-1, 1] {
                let corner = NSPoint(
                    x: frame.midX + horizontal * frame.width / 2,
                    y: frame.midY + vertical * frame.height / 2
                )
                let end = NSPoint(x: corner.x, y: corner.y - vertical * cornerLength)
                corners.move(to: NSPoint(x: corner.x - horizontal * cornerLength, y: corner.y))
                corners.appendArc(from: corner, to: end, radius: cornerRadius)
                corners.line(to: end)
            }
        }
        NSColor.black.withAlphaComponent(0.6).setStroke()
        corners.lineWidth = 5
        corners.stroke()
        NSColor.white.setStroke()
        corners.lineWidth = 3
        corners.stroke()
    }
}
