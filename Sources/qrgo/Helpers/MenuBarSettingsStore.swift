import Foundation

enum MenuBarSettingsStore {
    static let scanShortcutDidChange = Notification.Name("MenuBarSettingsStore.scanShortcutDidChange")

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

    static var userDefaults = UserDefaults.standard

    private static let scanShortcutKey = "menuBar.scanShortcut"
}
