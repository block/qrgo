import XCTest
@testable import qrgo

final class MenuBarLaunchHelperTests: XCTestCase {
    func testAgentArgumentsPreserveMenuBarConfigurationFlags() {
        let arguments = MenuBarLaunchHelper.agentArguments(from: [
            "qrgo",
            MenuBarLaunchHelper.launchArgument,
            "--transform-urls",
            "--copy"
        ])

        XCTAssertEqual(arguments, [
            MenuBarLaunchHelper.agentArgument,
            "--transform-urls"
        ])
    }

    func testAgentArgumentsDropUnsupportedFlags() {
        let arguments = MenuBarLaunchHelper.agentArguments(from: [
            "qrgo",
            "--menu-bar",
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
}
