import Foundation

struct AndroidDeviceDiscovery {
    let devices: [String]
    let toolingWarning: String?
}

class AndroidEmulatorHelper {
    static func findAdbPath() -> String? {
        if let cachedAdbPath = _cachedAdbPath {
            return cachedAdbPath
        }

        guard let adbPath = resolveAdbPath() else {
            QRGoLogger.menuBarWarning("ADB path resolution failed.")
            return nil
        }

        QRGoLogger.menuBarInfo("Resolved ADB path: \(adbPath)")
        _cachedAdbPath = adbPath
        return adbPath
    }

    static func getRunningDevices() -> [String] {
        return getRunningDeviceDiscovery().devices
    }

    static func getRunningDeviceDiscovery() -> AndroidDeviceDiscovery {
        guard let adbPath = findAdbPath() else {
            printError("ADB not found. Please install Android SDK or ensure ADB is in your PATH.")
            return AndroidDeviceDiscovery(
                devices: [],
                toolingWarning: "Android tooling not found. QRGo could not find adb from this app session."
            )
        }

        let result = Shell.runCommand(adbPath, arguments: ["devices"], mergeStderr: true)
        guard result.succeeded else {
            logEmptyAdbDevicesResult(result)
            return AndroidDeviceDiscovery(devices: [], toolingWarning: nil)
        }

        let devices = parseRunningDeviceIds(fromAdbDevicesOutput: result.stdout)
        if devices.isEmpty {
            logEmptyAdbDevicesResult(result)
        }
        return AndroidDeviceDiscovery(devices: devices, toolingWarning: nil)
    }

    static func parseRunningDeviceIds(fromAdbDevicesOutput output: String) -> [String] {
        return output.components(separatedBy: .newlines).compactMap { line in
            let components = line.split { character in
                character == " " || character == "\t"
            }
            return components.count >= 2 && components[1] == "device" ? String(components[0]) : nil
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

    private static var _cachedAdbPath: String?

    private static func resolveAdbPath() -> String? {
        let result = Shell.runLoginShell("command -v adb")
        if result.succeeded,
           let adbPath = firstExecutablePath(in: result.stdout) {
            return adbPath
        }

        for path in fallbackAdbPaths() where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        return nil
    }

    private static func logEmptyAdbDevicesResult(_ result: ShellResult) {
        let output = result.trimmedOutput.isEmpty ? "(empty)" : result.trimmedOutput
        QRGoLogger.menuBarWarning(
            "ADB devices returned no usable Android devices. " +
                "exitCode=\(result.exitCode), timedOut=\(result.timedOut), output=\(output)"
        )
    }

    private static func firstExecutablePath(in output: String) -> String? {
        for line in output.components(separatedBy: .newlines) {
            let path = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    private static func fallbackAdbPaths(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String] {
        var paths: [String] = []

        for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            guard let sdkRoot = environment[key], !sdkRoot.isEmpty else {
                continue
            }
            paths.append(adbPath(inAndroidSdkRoot: URL(fileURLWithPath: sdkRoot)))
        }

        paths.append(adbPath(inAndroidSdkRoot: homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Android", isDirectory: true)
            .appendingPathComponent("sdk", isDirectory: true)))
        paths.append("/opt/homebrew/bin/adb")
        paths.append("/usr/local/bin/adb")

        var seenPaths = Set<String>()
        return paths.filter { path in
            seenPaths.insert(path).inserted
        }
    }

    private static func adbPath(inAndroidSdkRoot sdkRoot: URL) -> String {
        return sdkRoot
            .appendingPathComponent("platform-tools", isDirectory: true)
            .appendingPathComponent("adb", isDirectory: false)
            .path
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
}
