import XCTest
@testable import qrgo

final class LoginItemHelperTests: XCTestCase {
    func testLaunchctlListOutputDetectsManagedProcessPID() {
        let output = """
        {
            "Label" = "com.block.qrgo.menubar";
            "PID" = 12345;
        };
        """

        XCTAssertTrue(LoginItemHelper.launchctlListOutput(output, managesPID: 12345))
    }

    func testLaunchctlListOutputIgnoresOtherProcessPID() {
        let output = """
        {
            "Label" = "com.block.qrgo.menubar";
            "PID" = 54321;
        };
        """

        XCTAssertFalse(LoginItemHelper.launchctlListOutput(output, managesPID: 12345))
    }

    func testLaunchctlListOutputIgnoresLoadedAgentWithoutPID() {
        let output = """
        {
            "Label" = "com.block.qrgo.menubar";
            "LastExitStatus" = 0;
        };
        """

        XCTAssertFalse(LoginItemHelper.launchctlListOutput(output, managesPID: 12345))
    }
}
