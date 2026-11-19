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

private extension TargetOption {
    var devicePreferenceKey: String? {
        switch action {
        case .ios, .local:
            return action.key
        case .android:
            return androidPreferenceKey
        case .copy, .skip:
            return nil
        }
    }
}

private extension Array where Element == TargetOption {
    func uniqueDevice(matching key: String) -> TargetOption? {
        let matches = filter { $0.devicePreferenceKey == key }
        return matches.count == 1 ? matches.first : nil
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
        guard let key = preferredDeviceKey() else {
            return await fallback.selectTarget(for: urlString, from: options, footerWarning: footerWarning)
        }
        if let option = options.uniqueDevice(matching: key) {
            return option.action
        }

        let warning = ["The selected device is unavailable. Choose another destination.", footerWarning]
            .compactMap { $0 }
            .joined(separator: "\n")
        return await fallback.selectTarget(for: urlString, from: options, footerWarning: warning)
    }
}

/// Refreshes device discovery without blocking AppKit's menu tracking.
@MainActor
final class MenuBarDeviceMenu: NSObject, NSMenuDelegate {
    let menu = NSMenu(title: "Default Device")
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
        let targets = await loadTargets()
        guard !Task.isCancelled, targets != availableTargets else { return }
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
        addChoice(title: "No default", key: nil, selectedKey: selectedKey)
        menu.addItem(.separator())

        guard let availableTargets = availableTargets else {
            addStatus("Loading devices…")
            return
        }

        let devices = availableTargets.options.filter { $0.action.isDeviceDestination }
        if let selectedKey = selectedKey, devices.uniqueDevice(matching: selectedKey) == nil {
            let unavailableItem = addStatus("Unavailable: \(selectedKey)")
            unavailableItem.state = .on
        }
        for device in devices {
            let item: NSMenuItem
            if let key = device.devicePreferenceKey, devices.uniqueDevice(matching: key) != nil {
                item = addChoice(title: device.displayName, key: key, selectedKey: selectedKey)
                item.toolTip = key
            } else {
                item = addStatus(device.displayName)
                item.toolTip = "This device cannot be selected for automatic delivery."
            }
            item.image = NSImage(systemSymbolName: device.systemSymbolName, accessibilityDescription: nil)
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
