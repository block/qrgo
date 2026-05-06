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
        appDelegate = delegate

        app.run()
    }

    private static var appDelegate: MenuBarAppDelegate?
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
    private var isScanning = false
    private var statusItem: NSStatusItem?

    init(configuration: QRGoRunConfiguration) {
        self.configuration = configuration
        super.init()
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
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.statusItem = statusItem
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            startScan()
        }
    }

    @objc private func startScan() {
        guard !isScanning else {
            notifier.warning("QRGo is already scanning.")
            return
        }

        QRGoLogger.menuBarInfo("Starting QR scan from menu bar.")
        isScanning = true
        Task { @MainActor in
            let runner = QRGoRunner(
                configuration: configuration,
                targetSelector: AppKitTargetSelector(),
                notifier: notifier
            )
            _ = await runner.run()
            isScanning = false
        }
    }

    @objc private func toggleLoginItem() {
        QRGoLogger.menuBarInfo("Toggling QRGo launch-at-login setting.")

        let succeeded: Bool
        if LoginItemHelper.isInstalled {
            succeeded = LoginItemHelper.uninstall()
        } else {
            succeeded = LoginItemHelper.install(loadImmediately: false)
        }

        if !succeeded {
            notifier.error("Could not update the QRGo login item.")
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showMenu() {
        guard let statusItem = statusItem else { return }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Scan QR Code", action: #selector(startScan), keyEquivalent: ""))
        menu.addItem(.separator())

        let loginTitle = LoginItemHelper.isInstalled ? "Disable Launch at Login" : "Enable Launch at Login"
        menu.addItem(NSMenuItem(title: loginTitle, action: #selector(toggleLoginItem), keyEquivalent: ""))
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

@MainActor
final class MenuBarNotifier: QRGoNotifying {
    let reportsDeviceOpenResults = true
    let reportsSuccessfulDeviceOpenResults = false

    func error(_ message: String) {
        QRGoLogger.menuBarError(message)
        showAlert(title: "QRGo", message: message, style: .critical)
    }

    func info(_ message: String) {
        QRGoLogger.menuBarInfo(message)
    }

    func success(_ message: String) {
        QRGoLogger.menuBarInfo(message)
        showAlert(title: "QRGo", message: message, style: .informational)
    }

    func warning(_ message: String) {
        QRGoLogger.menuBarWarning(message)
        showAlert(title: "QRGo", message: message, style: .warning)
    }

    private func showAlert(title: String, message: String, style: NSAlert.Style) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
