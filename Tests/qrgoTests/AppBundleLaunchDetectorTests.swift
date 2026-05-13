import XCTest
@testable import qrgo

final class AppBundleLaunchDetectorTests: XCTestCase {
    func testDetectsPackagedAppLaunchWithNoArguments() {
        XCTAssertTrue(
            AppBundleLaunchDetector.shouldLaunchMenuBarApp(
                arguments: ["/Applications/QRGo.app/Contents/MacOS/QRGo"],
                bundleIdentifier: AppBundleLaunchDetector.bundleIdentifier
            )
        )
    }

    func testIgnoresNonBundledCliLaunch() {
        XCTAssertFalse(
            AppBundleLaunchDetector.shouldLaunchMenuBarApp(
                arguments: ["qrgo"],
                bundleIdentifier: nil
            )
        )
    }

    func testIgnoresBundledLaunchWithArguments() {
        XCTAssertFalse(
            AppBundleLaunchDetector.shouldLaunchMenuBarApp(
                arguments: [
                    "/Applications/QRGo.app/Contents/MacOS/QRGo",
                    MenuBarLaunchHelper.agentArgument
                ],
                bundleIdentifier: AppBundleLaunchDetector.bundleIdentifier
            )
        )
    }

    func testAllowsBundledLaunchWithProcessSerialNumberArgument() {
        XCTAssertTrue(
            AppBundleLaunchDetector.shouldLaunchMenuBarApp(
                arguments: [
                    "/Applications/QRGo.app/Contents/MacOS/QRGo",
                    "-psn_0_12345"
                ],
                bundleIdentifier: AppBundleLaunchDetector.bundleIdentifier
            )
        )
    }
}
