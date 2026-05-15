import AppKit

/// Shared frontmost window styling for menu bar modal workflows.
@MainActor
enum MenuBarModalWindow {
    static func configure(_ window: NSWindow) {
        window.styleMask = [.titled, .closable]
        window.isMovable = true
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.level = .modalPanel
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }

    static func show(_ window: NSWindow) {
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
