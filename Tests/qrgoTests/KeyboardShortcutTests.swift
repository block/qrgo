import AppKit
import XCTest
@testable import qrgo

final class KeyboardShortcutTests: XCTestCase {
    func testDefaultScanShortcutUsesTwoEasyToPressModifiers() {
        XCTAssertEqual(
            KeyboardShortcut.defaultScan,
            KeyboardShortcut(
                keyCode: KeyboardShortcutKeyCode.letterQ,
                modifiers: [.control, .shift]
            )
        )
    }

    func testValidationAllowsShiftAsSecondModifier() {
        let shortcut = KeyboardShortcut(
            keyCode: 999,
            modifiers: [.control, .shift]
        )

        XCTAssertNil(
            KeyboardShortcutValidator.validationMessage(
                for: shortcut,
                currentShortcut: shortcut
            )
        )
    }

    func testValidationRejectsSingleModifierShortcut() {
        let shortcut = KeyboardShortcut(
            keyCode: KeyboardShortcutKeyCode.letterQ,
            modifiers: [.shift]
        )

        XCTAssertEqual(
            KeyboardShortcutValidator.validationMessage(
                for: shortcut,
                currentShortcut: shortcut
            ),
            KeyboardShortcutValidator.minimumModifierMessage
        )
    }

    func testValidationRejectsKnownMacOSShortcut() {
        let shortcut = KeyboardShortcut(
            keyCode: KeyboardShortcutKeyCode.letterQ,
            modifiers: [.command, .shift]
        )

        XCTAssertEqual(
            KeyboardShortcutValidator.validationMessage(
                for: shortcut,
                currentShortcut: shortcut
            ),
            "⇧⌘Q conflicts with a macOS keyboard shortcut."
        )
    }
}
