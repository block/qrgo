import Foundation

enum MenuBarSettingsStore {
    static let scanShortcutDidChange = Notification.Name("MenuBarSettingsStore.scanShortcutDidChange")
    static let defaultsDomain = "com.block.qrgo"

    /// `nil` means QRGo has not recorded explicit user intent yet.
    /// Callers should fall back to the current LaunchAgent state for legacy installs.
    static var launchAtLoginPreference: Bool? {
        get {
            guard userDefaults.object(forKey: launchAtLoginKey) != nil else {
                return nil
            }
            return userDefaults.bool(forKey: launchAtLoginKey)
        }
        set {
            if let newValue = newValue {
                userDefaults.set(newValue, forKey: launchAtLoginKey)
            } else {
                userDefaults.removeObject(forKey: launchAtLoginKey)
            }
        }
    }

    static var scanShortcut: KeyboardShortcut {
        get {
            guard let data = userDefaults.data(forKey: scanShortcutKey),
                  let shortcut = try? JSONDecoder().decode(KeyboardShortcut.self, from: data) else {
                return .defaultScan
            }
            return shortcut
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else {
                return
            }
            userDefaults.set(data, forKey: scanShortcutKey)
            NotificationCenter.default.post(name: scanShortcutDidChange, object: nil)
        }
    }

    static func resetScanShortcut() {
        userDefaults.removeObject(forKey: scanShortcutKey)
        NotificationCenter.default.post(name: scanShortcutDidChange, object: nil)
    }

    static var defaultUserDefaults: UserDefaults {
        defaultUserDefaults(bundleIdentifier: Bundle.main.bundleIdentifier)
    }

    static var userDefaults = defaultUserDefaults

    /// App bundle processes already write to `com.block.qrgo`; CLI and test runners need the shared domain.
    static func defaultUserDefaults(bundleIdentifier: String?) -> UserDefaults {
        defaultUserDefaults(
            bundleIdentifier: bundleIdentifier,
            standardDefaults: .standard,
            sharedDefaults: UserDefaults(suiteName: defaultsDomain)
        )
    }

    static func defaultUserDefaults(
        bundleIdentifier: String?,
        standardDefaults: UserDefaults,
        sharedDefaults: UserDefaults?
    ) -> UserDefaults {
        guard bundleIdentifier != defaultsDomain else {
            return standardDefaults
        }
        guard let sharedDefaults = sharedDefaults else {
            return standardDefaults
        }

        migrateLegacyDefaults(from: standardDefaults, to: sharedDefaults)
        return sharedDefaults
    }

    private static let launchAtLoginKey = "menuBar.launchAtLogin"
    private static let scanShortcutKey = "menuBar.scanShortcut"
    private static let legacyMigratedKeys = [
        launchAtLoginKey,
        scanShortcutKey
    ]

    private static func migrateLegacyDefaults(from legacyDefaults: UserDefaults, to sharedDefaults: UserDefaults) {
        for key in legacyMigratedKeys where sharedDefaults.object(forKey: key) == nil {
            if let legacyValue = legacyDefaults.object(forKey: key) {
                sharedDefaults.set(legacyValue, forKey: key)
            }
        }
    }
}
