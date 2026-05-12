import XCTest
@testable import qrgo

final class MenuBarSettingsStoreTests: XCTestCase {
    private var suiteName: String?
    private var userDefaults: UserDefaults?

    override func setUpWithError() throws {
        try super.setUpWithError()

        let suiteName = "com.block.qrgo.tests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)

        self.suiteName = suiteName
        self.userDefaults = userDefaults
        MenuBarSettingsStore.userDefaults = userDefaults
    }

    override func tearDown() {
        if let suiteName = suiteName {
            userDefaults?.removePersistentDomain(forName: suiteName)
        }
        MenuBarSettingsStore.userDefaults = .standard
        super.tearDown()
    }

    func testResetScanShortcutRestoresDefaultShortcut() {
        let customShortcut = KeyboardShortcut(
            keyCode: KeyboardShortcutKeyCode.letterD,
            modifiers: [.control, .option]
        )

        MenuBarSettingsStore.scanShortcut = customShortcut
        MenuBarSettingsStore.resetScanShortcut()

        XCTAssertEqual(MenuBarSettingsStore.scanShortcut, .defaultScan)
    }
}
