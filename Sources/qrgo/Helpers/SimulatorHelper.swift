import Foundation

class SimulatorHelper {
    static func getBootedSimulator() -> String? {
        let result = Shell.runCommand("/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "booted", "-j"])
        guard result.succeeded,
              let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = json["devices"] as? [String: [[String: Any]]] else {
            return nil
        }
        for deviceList in devices.values {
            if let device = deviceList.first(where: { ($0["state"] as? String) == "Booted" }),
               let udid = device["udid"] as? String {
                return udid
            }
        }
        return nil
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
