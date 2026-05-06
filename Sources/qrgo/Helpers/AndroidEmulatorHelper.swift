import Foundation

class AndroidEmulatorHelper {
    private static var _cachedAdbPath: String?
    private static var _adbPathChecked = false

    static func findAdbPath() -> String? {
        if _adbPathChecked {
            return _cachedAdbPath
        }

        let result = Shell.runLoginShell("which adb")
        if result.succeeded, !result.trimmedOutput.isEmpty {
            _cachedAdbPath = result.trimmedOutput
        }

        _adbPathChecked = true
        return _cachedAdbPath
    }

    static func getRunningDevices() -> [String] {
        guard let adbPath = findAdbPath() else {
            printError("ADB not found. Please install Android SDK or ensure ADB is in your PATH.")
            return []
        }

        let result = Shell.runCommand(adbPath, arguments: ["devices"])
        guard result.succeeded else { return [] }

        return result.stdout.components(separatedBy: .newlines).compactMap { line in
            let components = line.components(separatedBy: .whitespaces)
            return (components.count >= 2 && components[1] == "device") ? components[0] : nil
        }
    }

    static func getDeviceFriendlyName(_ deviceId: String) -> String {
        guard let adbPath = findAdbPath() else {
            return "Android Device (\(deviceId))"
        }

        let props = getDeviceProperties(deviceId: deviceId, adbPath: adbPath)
        let model = props["ro.product.model"] ?? ""
        let manufacturer = props["ro.product.manufacturer"] ?? ""
        let apiLevel = props["ro.build.version.sdk"] ?? ""
        let isQemu = props["ro.kernel.qemu"] ?? ""
        let avdName = props["ro.boot.qemu.avd_name"] ?? ""

        let isEmulator = isQemu == "1" || deviceId.contains("emulator-")

        var displayName = ""

        if isEmulator {
            if !avdName.isEmpty {
                let cleanedAvdName = avdName.replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: "API", with: "API ")
                displayName = "\(cleanedAvdName) (Emulator)"
            } else if !model.isEmpty {
                if !apiLevel.isEmpty {
                    displayName = "\(model) API \(apiLevel) (Emulator)"
                } else {
                    displayName = "\(model) (Emulator)"
                }
            } else {
                displayName = "Android Emulator (\(deviceId))"
            }
        } else {
            if !manufacturer.isEmpty && !model.isEmpty {
                if model.lowercased().contains(manufacturer.lowercased()) {
                    displayName = "\(model)"
                } else {
                    displayName = "\(manufacturer) \(model)"
                }
            } else if !model.isEmpty {
                displayName = "\(model)"
            } else if !manufacturer.isEmpty {
                displayName = "\(manufacturer) Device"
            } else {
                displayName = "Android Device (\(deviceId))"
            }
        }

        return displayName
    }

    private static func getDeviceProperties(deviceId: String, adbPath: String) -> [String: String] {
        let properties = [
            "ro.product.model",
            "ro.product.manufacturer",
            "ro.build.version.sdk",
            "ro.kernel.qemu",
            "ro.boot.qemu.avd_name"
        ]

        let shellCommand = properties.map { "getprop \($0)" }.joined(separator: " && echo '|||' && ")
        let result = Shell.runCommand(adbPath, arguments: ["-s", deviceId, "shell", shellCommand], suppressStderr: true)
        guard result.succeeded else { return [:] }

        var props: [String: String] = [:]
        let values = result.stdout.components(separatedBy: "|||").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for (index, prop) in properties.enumerated() where index < values.count {
            props[prop] = values[index]
        }
        return props
    }

    private static func validateAndSanitizeUrl(_ urlString: String) -> String? {
        switch sanitizeUrlForAndroidShell(urlString) {
        case .success(let safe):
            return safe
        case .failure(.malformed):
            printError("Malformed or unsupported URL, cannot open on Android device.")
            return nil
        case .failure(.disallowedScheme(let scheme)):
            printError(
                "URL scheme '\(scheme.isEmpty ? "(none)" : scheme)' is not allowed. " +
                    "Only http, https, and cashme are permitted."
            )
            return nil
        case .failure(.dangerousCharacters):
            printError("URL contains characters that are not permitted for Android shell.")
            return nil
        }
    }

    @discardableResult
    static func openUrl(_ urlString: String, deviceId: String? = nil, validated: Bool = false) -> Bool {
        guard let adbPath = findAdbPath() else {
            printError("ADB not found. Please install Android SDK or ensure ADB is in your PATH.")
            return false
        }

        guard let safeUrlString = validateAndSanitizeUrl(urlString) else {
            return false
        }

        let targetDevice: String
        if let deviceId = deviceId, validated {
            targetDevice = deviceId
        } else {
            let devices = getRunningDevices()
            guard !devices.isEmpty else {
                printError("No running Android devices found")
                return false
            }

            if let deviceId = deviceId, devices.contains(deviceId) {
                targetDevice = deviceId
            } else {
                targetDevice = devices[0]
            }
        }

        // `adb shell <string>` passes the string to `/bin/sh -c` on the Android device.
        // The URL is wrapped in single quotes so the shell treats &, ;, |, etc. as literal
        // URL data rather than shell operators. The sanitizer guarantees the URL contains no
        // single quotes, making breakout from the single-quoted string impossible.
        let shellCommand = [
            "am start",
            "-a android.intent.action.VIEW",
            "-c android.intent.category.BROWSABLE",
            "-d '\(safeUrlString)'"
        ].joined(separator: " ")
        let result = Shell.runCommand(
            adbPath,
            arguments: ["-s", targetDevice, "shell", shellCommand],
            mergeStderr: true
        )
        let deviceName = getDeviceFriendlyName(targetDevice)

        if !result.succeeded || result.stdout.contains("Error:") {
            if result.stdout.contains("unable to resolve Intent") {
                printError("\nNo app on \(deviceName) can handle this URL.")
            } else {
                printError("\nFailed to open URL on \(deviceName)")
                if !result.trimmedOutput.isEmpty {
                    printError(result.trimmedOutput)
                }
            }
            return false
        } else {
            printSuccess("\nOpened URL on \(deviceName)")
            return true
        }
    }
}
