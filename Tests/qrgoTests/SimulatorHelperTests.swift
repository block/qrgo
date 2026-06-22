import XCTest
@testable import qrgo

final class SimulatorHelperTests: XCTestCase {
    func testParseBootedSimulatorsReturnsAllBootedDevices() {
        let output = """
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-26-2": [
              {
                "name": "BAZEL_TEST_iPhone 16 Pro_26.2",
                "udid": "72B33203-A91F-463B-AACF-F3B6AE52DA4F",
                "state": "Booted"
              },
              {
                "name": "iPhone 17 Pro Max",
                "udid": "64BE9A7E-A99B-41C9-A7AF-2DA2227FF88A",
                "state": "Booted"
              },
              {
                "name": "iPhone 15",
                "udid": "A4C0AF79-4D8F-4386-92C4-D668A50A4270",
                "state": "Shutdown"
              }
            ]
          }
        }
        """

        XCTAssertEqual(
            SimulatorHelper.parseBootedSimulators(fromSimctlJSON: output),
            [
                BootedIOSSimulator(
                    name: "BAZEL_TEST_iPhone 16 Pro_26.2",
                    udid: "72B33203-A91F-463B-AACF-F3B6AE52DA4F"
                ),
                BootedIOSSimulator(
                    name: "iPhone 17 Pro Max",
                    udid: "64BE9A7E-A99B-41C9-A7AF-2DA2227FF88A"
                )
            ]
        )
    }

    func testParseBootedSimulatorsIgnoresMalformedOutput() {
        XCTAssertEqual(
            SimulatorHelper.parseBootedSimulators(fromSimctlJSON: "not json"),
            []
        )
    }

    func testParseBootedSimulatorsFallsBackToGenericName() {
        let output = """
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-26-2": [
              {
                "name": "",
                "udid": "64BE9A7E-A99B-41C9-A7AF-2DA2227FF88A",
                "state": "Booted"
              }
            ]
          }
        }
        """

        XCTAssertEqual(
            SimulatorHelper.parseBootedSimulators(fromSimctlJSON: output),
            [
                BootedIOSSimulator(
                    name: "iOS Simulator",
                    udid: "64BE9A7E-A99B-41C9-A7AF-2DA2227FF88A"
                )
            ]
        )
    }

    func testGenericSimulatorDisplayNameOmitsUDID() {
        let simulator = BootedIOSSimulator(
            name: "iOS Simulator",
            udid: "64BE9A7E-A99B-41C9-A7AF-2DA2227FF88A"
        )

        XCTAssertEqual(
            simulator.displayName,
            "Simulator"
        )
    }

    func testNamedSimulatorDisplayNameUsesSimulatorLabelWithoutUDID() {
        let simulator = BootedIOSSimulator(
            name: "iPhone 17 Pro Max",
            udid: "64BE9A7E-A99B-41C9-A7AF-2DA2227FF88A"
        )

        XCTAssertEqual(
            simulator.displayName,
            "iPhone 17 Pro Max (Simulator)"
        )
    }

    func testNamedSimulatorDisplayNameReplacesUnderscores() {
        let simulator = BootedIOSSimulator(
            name: "BAZEL_TEST_iPhone 16 Pro_26.2",
            udid: "72B33203-A91F-463B-AACF-F3B6AE52DA4F"
        )

        XCTAssertEqual(
            simulator.displayName,
            "BAZEL TEST iPhone 16 Pro 26.2 (Simulator)"
        )
    }

    func testNamedSimulatorDisplayNameAbbreviatesGeneration() {
        let simulator = BootedIOSSimulator(
            name: "BAZEL_TEST_iPhone SE (3rd generation)_17.5",
            udid: "72B33203-A91F-463B-AACF-F3B6AE52DA4F"
        )

        XCTAssertEqual(
            simulator.displayName,
            "BAZEL TEST iPhone SE (3rd gen) 17.5 (Simulator)"
        )
    }
}
