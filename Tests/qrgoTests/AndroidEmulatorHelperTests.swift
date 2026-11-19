import XCTest
@testable import qrgo

final class AndroidEmulatorHelperTests: XCTestCase {
    func testParseRunningDeviceIdsHandlesTabSeparatedOutput() {
        let output = """
        List of devices attached
        emulator-5560\tdevice

        """

        XCTAssertEqual(
            AndroidEmulatorHelper.parseRunningDevices(fromAdbDevicesOutput: output).map(\.id),
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
            AndroidEmulatorHelper.parseRunningDevices(fromAdbDevicesOutput: output).map(\.id),
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
            AndroidEmulatorHelper.parseRunningDevices(fromAdbDevicesOutput: output).map(\.id),
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
            AndroidEmulatorHelper.parseRunningDevices(fromAdbDevicesOutput: output).map(\.id),
            ["emulator-5558"]
        )
    }

    func testParseRunningDevicesCapturesTransportID() {
        let output = "emulator-5554 device product:sdk model:Pixel transport_id:7"
        let devices = AndroidEmulatorHelper.parseRunningDevices(fromAdbDevicesOutput: output)

        XCTAssertEqual(devices, [AndroidDeviceConnection(id: "emulator-5554", transportID: 7)])
        XCTAssertEqual(devices.first?.adbArguments, ["-t", "7"])
    }
}
