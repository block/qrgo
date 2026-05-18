import XCTest
@testable import qrgo

@MainActor
final class MenuBarRelaunchHelperTests: XCTestCase {
    func testRelaunchArgumentsPreserveMenuBarConfigurationFlags() {
        let arguments = MenuBarRelaunchHelper.relaunchArguments(from: [
            "qrgo",
            MenuBarLaunchHelper.agentArgument,
            "--transform-urls",
            "--copy"
        ])

        XCTAssertEqual(arguments, [
            MenuBarLaunchHelper.agentArgument,
            "--transform-urls"
        ])
    }

    func testRelaunchArgumentsDropUnsupportedFlags() {
        let arguments = MenuBarRelaunchHelper.relaunchArguments(from: [
            "qrgo",
            "--menu-bar-agent",
            "--device",
            "emulator-5554",
            "-t",
            "-c"
        ])

        XCTAssertEqual(arguments, [
            MenuBarLaunchHelper.agentArgument,
            "-t"
        ])
    }

    func testRelaunchScriptWaitsForCurrentProcessToExit() {
        let script = MenuBarRelaunchHelper.relaunchScript(
            command: "/usr/bin/open '/Applications/QRGo.app'",
            currentPID: 12345
        )

        XCTAssertEqual(
            script,
            "while kill -0 12345 2>/dev/null; do sleep 0.1; done; /usr/bin/open '/Applications/QRGo.app'"
        )
    }
}
