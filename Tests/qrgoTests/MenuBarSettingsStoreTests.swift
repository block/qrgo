import AppKit
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
        MenuBarSettingsStore.launchAtLoginPreference = nil
        MenuBarSettingsStore.userDefaults = MenuBarSettingsStore.defaultUserDefaults
        super.tearDown()
    }

    func testLaunchAtLoginPreferenceDefaultsToNil() {
        XCTAssertNil(MenuBarSettingsStore.launchAtLoginPreference)
    }

    func testCaptureModeDefaultsToDrag() {
        XCTAssertEqual(MenuBarSettingsStore.captureMode, .drag)
    }

    func testCaptureModeFallsBackToDragForAnUnknownSavedValue() {
        userDefaults?.set("unknown", forKey: "menuBar.captureMode")
        XCTAssertEqual(MenuBarSettingsStore.captureMode, .drag)
    }

    func testCaptureModePersistsAcrossDefaultsInstancesAndCanSwitchBack() throws {
        MenuBarSettingsStore.captureMode = .click
        MenuBarSettingsStore.userDefaults = try XCTUnwrap(UserDefaults(suiteName: XCTUnwrap(suiteName)))
        XCTAssertEqual(MenuBarSettingsStore.captureMode, .click)

        MenuBarSettingsStore.captureMode = .drag
        MenuBarSettingsStore.userDefaults = try XCTUnwrap(UserDefaults(suiteName: XCTUnwrap(suiteName)))
        XCTAssertEqual(MenuBarSettingsStore.captureMode, .drag)
    }

    @MainActor
    func testSettingsPickerRestoresAndUpdatesCaptureMode() throws {
        _ = NSApplication.shared
        MenuBarSettingsStore.captureMode = .click
        let controller = MenuBarSettingsWindowController(registeredShortcutProvider: { nil })
        let view = try XCTUnwrap(controller.window?.contentViewController?.view)
        let picker = try XCTUnwrap(view.subviews.compactMap { $0 as? NSPopUpButton }.first)
        XCTAssertEqual(picker.selectedItem?.title, "Click selection")

        picker.selectItem(withTitle: "Drag selection")
        picker.sendAction(picker.action, to: picker.target)
        XCTAssertEqual(MenuBarSettingsStore.captureMode, .drag)

        picker.selectItem(withTitle: "Click selection")
        picker.sendAction(picker.action, to: picker.target)
        XCTAssertEqual(MenuBarSettingsStore.captureMode, .click)
    }

    func testLaunchAtLoginPreferencePersistsEnabledState() {
        MenuBarSettingsStore.launchAtLoginPreference = true

        XCTAssertEqual(MenuBarSettingsStore.launchAtLoginPreference, true)
    }

    func testLaunchAtLoginPreferencePersistsDisabledState() {
        MenuBarSettingsStore.launchAtLoginPreference = false

        XCTAssertEqual(MenuBarSettingsStore.launchAtLoginPreference, false)
    }

    func testLaunchAtLoginPreferenceCanBeCleared() {
        MenuBarSettingsStore.launchAtLoginPreference = true
        MenuBarSettingsStore.launchAtLoginPreference = nil

        XCTAssertNil(MenuBarSettingsStore.launchAtLoginPreference)
    }

    func testDefaultUserDefaultsUsesStandardDefaultsInsideAppBundle() {
        XCTAssertTrue(
            MenuBarSettingsStore.defaultUserDefaults(bundleIdentifier: MenuBarSettingsStore.defaultsDomain) ===
                UserDefaults.standard
        )
    }

    func testDefaultUserDefaultsUsesSharedDomainOutsideAppBundle() {
        XCTAssertFalse(
            MenuBarSettingsStore.defaultUserDefaults(bundleIdentifier: nil) === UserDefaults.standard
        )
    }

    func testDefaultUserDefaultsMigratesLegacyStandardScanShortcutIntoSharedDomain() throws {
        let legacySuiteName = "com.block.qrgo.tests.legacy.\(UUID().uuidString)"
        let sharedSuiteName = "com.block.qrgo.tests.shared.\(UUID().uuidString)"
        let legacyDefaults = try XCTUnwrap(UserDefaults(suiteName: legacySuiteName))
        let sharedDefaults = try XCTUnwrap(UserDefaults(suiteName: sharedSuiteName))
        legacyDefaults.removePersistentDomain(forName: legacySuiteName)
        sharedDefaults.removePersistentDomain(forName: sharedSuiteName)
        defer {
            legacyDefaults.removePersistentDomain(forName: legacySuiteName)
            sharedDefaults.removePersistentDomain(forName: sharedSuiteName)
        }

        let legacyShortcut = KeyboardShortcut(
            keyCode: KeyboardShortcutKeyCode.letterD,
            modifiers: [.control, .option]
        )
        MenuBarSettingsStore.userDefaults = legacyDefaults
        MenuBarSettingsStore.scanShortcut = legacyShortcut

        MenuBarSettingsStore.userDefaults = MenuBarSettingsStore.defaultUserDefaults(
            bundleIdentifier: nil,
            standardDefaults: legacyDefaults,
            sharedDefaults: sharedDefaults
        )

        XCTAssertEqual(MenuBarSettingsStore.scanShortcut, legacyShortcut)
    }

    func testDefaultUserDefaultsDoesNotOverwriteSharedScanShortcutDuringMigration() throws {
        let legacySuiteName = "com.block.qrgo.tests.legacy.\(UUID().uuidString)"
        let sharedSuiteName = "com.block.qrgo.tests.shared.\(UUID().uuidString)"
        let legacyDefaults = try XCTUnwrap(UserDefaults(suiteName: legacySuiteName))
        let sharedDefaults = try XCTUnwrap(UserDefaults(suiteName: sharedSuiteName))
        legacyDefaults.removePersistentDomain(forName: legacySuiteName)
        sharedDefaults.removePersistentDomain(forName: sharedSuiteName)
        defer {
            legacyDefaults.removePersistentDomain(forName: legacySuiteName)
            sharedDefaults.removePersistentDomain(forName: sharedSuiteName)
        }

        let legacyShortcut = KeyboardShortcut(
            keyCode: KeyboardShortcutKeyCode.letterD,
            modifiers: [.control, .option]
        )
        let sharedShortcut = KeyboardShortcut(
            keyCode: KeyboardShortcutKeyCode.letterQ,
            modifiers: [.command, .control]
        )
        MenuBarSettingsStore.userDefaults = legacyDefaults
        MenuBarSettingsStore.scanShortcut = legacyShortcut
        MenuBarSettingsStore.userDefaults = sharedDefaults
        MenuBarSettingsStore.scanShortcut = sharedShortcut

        MenuBarSettingsStore.userDefaults = MenuBarSettingsStore.defaultUserDefaults(
            bundleIdentifier: nil,
            standardDefaults: legacyDefaults,
            sharedDefaults: sharedDefaults
        )

        XCTAssertEqual(MenuBarSettingsStore.scanShortcut, sharedShortcut)
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
