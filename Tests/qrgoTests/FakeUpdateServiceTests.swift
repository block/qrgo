import XCTest
@testable import qrgo

final class FakeUpdateServiceTests: XCTestCase {
    func testDryRunAvailableModeReturnsAvailableUpdateAndInstallSuccess() async {
        let service = FakeUpdateService(mode: .available, checkDelay: 0, installDelay: 0)

        let checkResult = await service.checkForUpdate(mode: .passive)
        let installResult = await service.installUpdate()

        XCTAssertEqual(checkResult, .available(MenuBarUpdate(installedVersion: "1.0.0", currentVersion: "9.9.9")))
        XCTAssertEqual(installResult, .installed)
    }

    func testDryRunCurrentModeReturnsCurrentUpdateState() async {
        let service = FakeUpdateService(mode: .current, checkDelay: 0, installDelay: 0)

        let checkResult = await service.checkForUpdate(mode: .passive)

        XCTAssertEqual(checkResult, .current)
    }

    func testDryRunCheckErrorModeReturnsCheckFailure() async {
        let service = FakeUpdateService(mode: .checkError, checkDelay: 0, installDelay: 0)

        let checkResult = await service.checkForUpdate(mode: .passive)

        guard case .failed(let error) = checkResult else {
            return XCTFail("Expected failed check result.")
        }
        XCTAssertEqual(error.message, "Dry-run update check failed.")
    }

    func testDryRunInstallErrorModeReturnsInstallFailure() async {
        let service = FakeUpdateService(mode: .installError, checkDelay: 0, installDelay: 0)

        let installResult = await service.installUpdate()

        guard case .failed(let error) = installResult else {
            return XCTFail("Expected failed install result.")
        }
        XCTAssertEqual(error.message, "Dry-run update install failed.")
    }

    func testInvalidDryRunModeDoesNotInvokeHomebrew() async throws {
        let service = try XCTUnwrap(FakeUpdateService.fromEnvironment([
            "QRGO_UPDATE_DRY_RUN": "typo",
            "QRGO_UPDATE_CHECK_DELAY_SECONDS": "0"
        ]))

        let checkResult = await service.checkForUpdate(mode: .passive)

        guard case .failed(let error) = checkResult else {
            return XCTFail("Expected failed check result.")
        }
        XCTAssertEqual(error.message, "Unknown QRGo update dry-run mode.")
        XCTAssertEqual(error.details, "QRGO_UPDATE_DRY_RUN=typo")
    }
}
