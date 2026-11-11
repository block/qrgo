import AppKit

extension TargetAction {
    var isDeviceDestination: Bool {
        switch self {
        case .ios, .android, .local:
            return true
        case .copy, .skip:
            return false
        }
    }
}

/// Uses an explicit menu preference only while that destination is available.
@MainActor
struct PreferredDeviceTargetSelector: QRGoTargetSelecting {
    let fallback: QRGoTargetSelecting
    var preferredDeviceKey: () -> String? = { MenuBarSettingsStore.preferredDeviceKey }

    func selectTarget(
        for urlString: String,
        from options: [TargetOption],
        footerWarning: String?
    ) async -> TargetAction? {
        let key = preferredDeviceKey()
        if let option = options.first(where: { $0.action.isDeviceDestination && $0.action.key == key }) {
            return option.action
        }

        let warning: String?
        if key != nil {
            warning = ["The selected device is unavailable. Choose another destination.", footerWarning]
                .compactMap { $0 }
                .joined(separator: "\n")
        } else {
            warning = footerWarning
        }
        return await fallback.selectTarget(for: urlString, from: options, footerWarning: warning)
    }
}

/// Refreshes device discovery without blocking AppKit's menu tracking.
@MainActor
final class MenuBarDeviceMenu: NSObject, NSMenuDelegate {
    let menu = NSMenu(title: "Devices")
    private var refreshTask: Task<Void, Never>?
    private var availableTargets: AvailableTargetOptions?
    private let loadTargets: () async -> AvailableTargetOptions
    private let readPreference: () -> String?
    private let writePreference: (String?) -> Void

    init(
        loadTargets: @escaping () async -> AvailableTargetOptions = {
            await Task.detached(priority: .userInitiated) {
                makeAvailableTargetOptions(includesCopyOption: false)
            }.value
        },
        readPreference: @escaping () -> String? = { MenuBarSettingsStore.preferredDeviceKey },
        writePreference: @escaping (String?) -> Void = { MenuBarSettingsStore.preferredDeviceKey = $0 }
    ) {
        self.loadTargets = loadTargets
        self.readPreference = readPreference
        self.writePreference = writePreference
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Reuse discovery if the user closes and reopens the menu before it finishes.
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            await self?.refreshDevices()
            self?.refreshTask = nil
        }
    }

    func refreshDevices() async {
        availableTargets = nil
        rebuildMenu()
        let targets = await loadTargets()
        guard !Task.isCancelled else { return }
        availableTargets = targets
        rebuildMenu()
    }

    @objc private func selectDevice(_ sender: NSMenuItem) {
        writePreference(sender.representedObject as? String)
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let selectedKey = readPreference()
        addChoice(title: "None", key: nil, selectedKey: selectedKey)
        menu.addItem(.separator())

        guard let availableTargets = availableTargets else {
            addStatus("Loading devices…")
            return
        }

        let devices = availableTargets.options.filter { $0.action.isDeviceDestination }
        if let selectedKey = selectedKey, !devices.contains(where: { $0.action.key == selectedKey }) {
            let unavailableItem = addStatus("Selected device unavailable")
            unavailableItem.state = .on
        }
        for device in devices {
            let item = addChoice(title: device.displayName, key: device.action.key, selectedKey: selectedKey)
            item.image = NSImage(systemSymbolName: device.systemSymbolName, accessibilityDescription: nil)
            item.toolTip = device.action.key
        }
        if devices.isEmpty {
            addStatus("No devices available")
        }
        if let warning = availableTargets.footerWarning {
            menu.addItem(.separator())
            addStatus(warning)
        }
    }

    @discardableResult
    private func addChoice(title: String, key: String?, selectedKey: String?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(selectDevice), keyEquivalent: "")
        item.target = self
        item.representedObject = key
        item.state = key == selectedKey ? .on : .off
        menu.addItem(item)
        return item
    }

    @discardableResult
    private func addStatus(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
        return item
    }
}
