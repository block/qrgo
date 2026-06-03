import XCTest
@testable import qrgo

final class LoginItemHelperTests: XCTestCase {
    func testLaunchAtLoginEnabledUsesStoredPreferenceWhenPresent() {
        XCTAssertTrue(LoginItemHelper.launchAtLoginIsEnabled(preference: true, isInstalled: false))
        XCTAssertFalse(LoginItemHelper.launchAtLoginIsEnabled(preference: false, isInstalled: true))
    }

    func testLaunchAtLoginEnabledFallsBackToInstalledStateWithoutPreference() {
        XCTAssertTrue(LoginItemHelper.launchAtLoginIsEnabled(preference: nil, isInstalled: true))
        XCTAssertFalse(LoginItemHelper.launchAtLoginIsEnabled(preference: nil, isInstalled: false))
    }

    func testReconcileRecordsInstalledStateWhenPreferenceIsMissing() {
        var recordedPreference: Bool?
        var installCount = 0

        let succeeded = LoginItemHelper.reconcileLaunchAtLoginPreference(
            preference: nil,
            isInstalledProvider: { true },
            setPreference: { recordedPreference = $0 },
            installLoginItem: {
                installCount += 1
                return true
            },
            log: { _ in },
            logError: { _ in }
        )

        XCTAssertTrue(succeeded)
        XCTAssertEqual(recordedPreference, true)
        XCTAssertEqual(installCount, 0)
    }

    func testReconcileKeepsPreferenceMissingWhenLaunchAgentIsAbsent() {
        var recordedPreferences = [Bool?]()
        var installCount = 0

        let succeeded = LoginItemHelper.reconcileLaunchAtLoginPreference(
            preference: nil,
            isInstalledProvider: { false },
            setPreference: { recordedPreferences.append($0) },
            installLoginItem: {
                installCount += 1
                return true
            },
            log: { _ in },
            logError: { _ in }
        )

        XCTAssertTrue(succeeded)
        XCTAssertTrue(recordedPreferences.isEmpty)
        XCTAssertEqual(installCount, 0)
    }

    func testReconcileDoesNotRestoreWhenPreferenceIsDisabled() {
        var installCount = 0

        let succeeded = LoginItemHelper.reconcileLaunchAtLoginPreference(
            preference: false,
            isInstalledProvider: { false },
            setPreference: { _ in },
            installLoginItem: {
                installCount += 1
                return true
            },
            log: { _ in },
            logError: { _ in }
        )

        XCTAssertTrue(succeeded)
        XCTAssertEqual(installCount, 0)
    }

    func testReconcileRestoresMissingLaunchAgentWhenPreferenceIsEnabled() {
        var installCount = 0

        let succeeded = LoginItemHelper.reconcileLaunchAtLoginPreference(
            preference: true,
            isInstalledProvider: { false },
            setPreference: { _ in },
            installLoginItem: {
                installCount += 1
                return true
            },
            log: { _ in },
            logError: { _ in }
        )

        XCTAssertTrue(succeeded)
        XCTAssertEqual(installCount, 1)
    }

    func testReconcileDoesNotRestoreWhenPreferenceIsEnabledAndLaunchAgentExists() {
        var installCount = 0

        let succeeded = LoginItemHelper.reconcileLaunchAtLoginPreference(
            preference: true,
            isInstalledProvider: { true },
            setPreference: { _ in },
            installLoginItem: {
                installCount += 1
                return true
            },
            log: { _ in },
            logError: { _ in }
        )

        XCTAssertTrue(succeeded)
        XCTAssertEqual(installCount, 0)
    }

    func testReconcileReturnsFalseWhenRestoreFails() {
        let succeeded = LoginItemHelper.reconcileLaunchAtLoginPreference(
            preference: true,
            isInstalledProvider: { false },
            setPreference: { _ in },
            installLoginItem: { false },
            log: { _ in },
            logError: { _ in }
        )

        XCTAssertFalse(succeeded)
    }

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
