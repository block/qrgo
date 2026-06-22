import Foundation

struct BootedIOSSimulator: Equatable, Sendable {
    let name: String
    let udid: String

    var displayName: String {
        if displayNameBase == "iOS Simulator" {
            return "Simulator"
        }
        return "\(displayNameBase) (Simulator)"
    }

    private var displayNameBase: String {
        name
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "generation", with: "gen")
    }
}

class SimulatorHelper {
    static func getBootedSimulators(suppressStderr: Bool = false) -> [BootedIOSSimulator] {
        let result = Shell.runCommand(
            "/usr/bin/xcrun",
            arguments: ["simctl", "list", "devices", "booted", "-j"],
            suppressStderr: suppressStderr
        )
        guard result.succeeded else {
            return []
        }
        return parseBootedSimulators(fromSimctlJSON: result.stdout)
    }

    static func getBootedSimulator() -> String? {
        getBootedSimulators().first?.udid
    }

    static func parseBootedSimulators(fromSimctlJSON output: String) -> [BootedIOSSimulator] {
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = json["devices"] as? [String: [[String: Any]]] else {
            return []
        }

        var bootedSimulators: [BootedIOSSimulator] = []
        for deviceList in devices.values {
            let simulators = deviceList.compactMap { device -> BootedIOSSimulator? in
                guard (device["state"] as? String) == "Booted",
                      let udid = device["udid"] as? String,
                      !udid.isEmpty else {
                    return nil
                }

                let name = (device["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "iOS Simulator"
                return BootedIOSSimulator(name: name, udid: udid)
            }
            bootedSimulators.append(contentsOf: simulators)
        }
        return bootedSimulators
    }

    @discardableResult
    static func openUrl(_ urlString: String, udid: String? = nil) -> Bool {
        let simulatorUDID: String
        if let providedUDID = udid {
            simulatorUDID = providedUDID
        } else {
            guard let bootedUDID = getBootedSimulator() else {
                printError("No booted iOS Simulator found")
                return false
            }
            simulatorUDID = bootedUDID
        }

        let result = Shell.runCommand(
            "/usr/bin/xcrun",
            arguments: ["simctl", "openurl", simulatorUDID, urlString],
            mergeStderr: true
        )
        if result.succeeded {
            printSuccess("Opened URL on iOS Simulator")
            return true
        } else {
            printError("Failed to open URL in iOS Simulator")
            if !result.trimmedOutput.isEmpty {
                printError(result.trimmedOutput)
            }
            return false
        }
    }
}
