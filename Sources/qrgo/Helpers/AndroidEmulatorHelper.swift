import Foundation

struct AndroidDeviceDiscovery {
    let devices: [AndroidDeviceConnection]
    let toolingWarning: String?
}

struct AndroidDeviceConnection: Equatable {
    let id: String
    let transportID: UInt64?

    var adbArguments: [String] {
        if let transportID = transportID {
            return ["-t", String(transportID)]
        }
        return ["-s", id]
    }
}

struct AndroidDeviceDetails {
    let displayName: String
    let preferenceKey: String?
}

class AndroidEmulatorHelper {
    static func findAdbPath() -> String? {
        if let cachedAdbPath = adbPathLock.withLock({ _cachedAdbPath }) {
            return cachedAdbPath
        }

        guard let adbPath = resolveAdbPath() else {
            QRGoLogger.menuBarWarning("ADB path resolution failed.")
            return nil
        }

        QRGoLogger.menuBarInfo("Resolved ADB path: \(adbPath)")
        adbPathLock.withLock { _cachedAdbPath = adbPath }
        return adbPath
    }

    static func getRunningDevices() -> [String] {
        return getRunningDeviceDiscovery().devices.map(\.id)
    }

    static func getRunningDeviceDiscovery() -> AndroidDeviceDiscovery {
        guard let adbPath = findAdbPath() else {
            printError("ADB not found. Please install Android SDK or ensure ADB is in your PATH.")
            return AndroidDeviceDiscovery(
                devices: [],
                toolingWarning: "Android tooling not found. QRGo could not find adb from this app session."
            )
        }

        let result = Shell.runCommand(adbPath, arguments: ["devices", "-l"], mergeStderr: true)
        guard result.succeeded else {
            logEmptyAdbDevicesResult(result)
            return AndroidDeviceDiscovery(devices: [], toolingWarning: nil)
        }

        let devices = parseRunningDevices(fromAdbDevicesOutput: result.stdout)
        if devices.isEmpty {
            logEmptyAdbDevicesResult(result)
        }
        return AndroidDeviceDiscovery(devices: devices, toolingWarning: nil)
    }

    static func parseRunningDevices(fromAdbDevicesOutput output: String) -> [AndroidDeviceConnection] {
        return output.components(separatedBy: .newlines).compactMap { line in
            let components = line.split(whereSeparator: \.isWhitespace)
            guard components.count >= 2, components[1] == "device" else { return nil }
            let prefix = "transport_id:"
            let transportID = components.dropFirst(2).first { $0.hasPrefix(prefix) }
                .flatMap { UInt64($0.dropFirst(prefix.count)) }
            return AndroidDeviceConnection(id: String(components[0]), transportID: transportID)
        }
    }

    static func getDeviceFriendlyName(_ deviceId: String, transportID: UInt64? = nil) -> String {
        getDeviceDetails(for: AndroidDeviceConnection(id: deviceId, transportID: transportID)).displayName
    }

    static func getDeviceDetails(for device: AndroidDeviceConnection) -> AndroidDeviceDetails {
        let properties = findAdbPath().map { getDeviceProperties(for: device, adbPath: $0) } ?? [:]
        return deviceDetails(for: device, properties: properties)
    }

    static func deviceDetails(for device: AndroidDeviceConnection, properties props: [String: String])
        -> AndroidDeviceDetails {
        let deviceId = device.id
        let model = props["ro.product.model"] ?? ""
        let manufacturer = props["ro.product.manufacturer"] ?? ""
        let apiLevel = props["ro.build.version.sdk"] ?? ""
        let isQemu = props["ro.kernel.qemu"] ?? ""
        let avdName = props["ro.boot.qemu.avd_name"] ?? ""

        let isEmulator = isQemu == "1" || props["ro.boot.qemu"] == "1" ||
            !avdName.isEmpty || deviceId.hasPrefix("emulator-")

        var displayName = ""

        if isEmulator {
            if !avdName.isEmpty {
                let cleanedAvdName = avdName.replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: "API", with: "API ")
                displayName = "\(cleanedAvdName) (Emulator)"
            } else if !model.isEmpty {
                let modelAndAPI = apiLevel.isEmpty ? model : "\(model) API \(apiLevel)"
                displayName = "\(modelAndAPI) (Emulator)"
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

        let preferenceKey: String?
        if isEmulator {
            // ADB reuses emulator ports. Bind delivery to the current transport and save the AVD name.
            preferenceKey = avdName.isEmpty || device.transportID == nil ? nil : "android-avd:\(avdName)"
        } else {
            preferenceKey = props.isEmpty ? nil : "android:\(deviceId)"
        }
        return AndroidDeviceDetails(displayName: displayName, preferenceKey: preferenceKey)
    }

    @discardableResult
    static func openUrl(
        _ urlString: String, deviceId: String? = nil, validated: Bool = false, transportID: UInt64? = nil
    ) -> Bool {
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
        let connection = AndroidDeviceConnection(id: targetDevice, transportID: transportID)
        let result = Shell.runCommand(
            adbPath,
            arguments: connection.adbArguments + ["shell", shellCommand],
            mergeStderr: true
        )
        let deviceName = getDeviceDetails(for: connection).displayName

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

    private static let adbPathLock = NSLock()
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

    private static func getDeviceProperties(for device: AndroidDeviceConnection, adbPath: String) -> [String: String] {
        let properties = [
            "ro.product.model",
            "ro.product.manufacturer",
            "ro.build.version.sdk",
            "ro.kernel.qemu",
            "ro.boot.qemu",
            "ro.boot.qemu.avd_name"
        ]

        let shellCommand = properties.map { "getprop \($0)" }.joined(separator: " && echo '|||' && ")
        let result = Shell.runCommand(
            adbPath, arguments: device.adbArguments + ["shell", shellCommand], suppressStderr: true
        )
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
