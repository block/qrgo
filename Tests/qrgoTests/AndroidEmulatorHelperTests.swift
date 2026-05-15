import XCTest
@testable import qrgo

final class AndroidEmulatorHelperTests: XCTestCase {
    func testParseRunningDeviceIdsHandlesTabSeparatedOutput() {
        let output = """
        List of devices attached
        emulator-5560\tdevice

        """

        XCTAssertEqual(
            AndroidEmulatorHelper.parseRunningDeviceIds(fromAdbDevicesOutput: output),
            ["emulator-5560"]
        )
    }

    func testParseRunningDeviceIdsHandlesSpaceAlignedOutput() {
        let output = """
        List of devices attached
        emulator-5554      device
        192.168.1.100:5555 device

        """

        XCTAssertEqual(
            AndroidEmulatorHelper.parseRunningDeviceIds(fromAdbDevicesOutput: output),
            ["emulator-5554", "192.168.1.100:5555"]
        )
    }

    func testParseRunningDeviceIdsIgnoresAdbDaemonStartupLines() {
        let output = """
        * daemon not running; starting now at tcp:5037
        * daemon started successfully
        List of devices attached
        emulator-5554\tdevice

        """

        XCTAssertEqual(
            AndroidEmulatorHelper.parseRunningDeviceIds(fromAdbDevicesOutput: output),
            ["emulator-5554"]
        )
    }

    func testParseRunningDeviceIdsIgnoresUnavailableDevices() {
        let output = """
        List of devices attached
        emulator-5554 offline
        emulator-5556 unauthorized
        emulator-5558 device

        """

        XCTAssertEqual(
            AndroidEmulatorHelper.parseRunningDeviceIds(fromAdbDevicesOutput: output),
            ["emulator-5558"]
        )
    }
}
