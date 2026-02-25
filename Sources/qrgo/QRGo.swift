import Foundation
import ScreenCaptureKit

func transformUrl(_ urlString: String) -> String {
    // List of domains that should trigger the schema change
    let domainsToTransform = [
        "cashstaging.app",
        "cash.app",
        "cash.me"
    ]
    
    let lowercasedUrl = urlString.lowercased()
    
    // If it's already a cashme:// URL, return as is
    if lowercasedUrl.starts(with: "cashme://") {
        return urlString
    }
    
    // Extract the domain from the URL by removing the scheme
    var domainAndPath = urlString
    if lowercasedUrl.starts(with: "https://") {
        domainAndPath = String(urlString.dropFirst("https://".count))
    } else if lowercasedUrl.starts(with: "http://") {
        domainAndPath = String(urlString.dropFirst("http://".count))
    }
    
    // Check if the domain part matches any in our list
    for domain in domainsToTransform {
        if domainAndPath.starts(with: domain.lowercased()) {
            return "cashme://" + domainAndPath
        }
    }
    
    return urlString
}

func copyUrlToClipboard(_ text: String) {
    let result = Shell.runCommand("/usr/bin/pbcopy", input: text)
    if result.succeeded {
        printSuccess("📋 Copied to clipboard: \(text)")
    } else {
        printError("Failed to copy to clipboard: \(result.stderr)")
    }
}

func parseDeviceArgument() -> String? {
    let args = CommandLine.arguments
    for (index, arg) in args.enumerated() {
        if (arg == "-d" || arg == "--device") && index + 1 < args.count {
            let nextArg = args[index + 1]
            // Ensure the next argument is not another flag
            if nextArg.hasPrefix("-") {
                printError("-d/--device requires a device ID, not '\(nextArg)'")
                exit(1)
            }
            return nextArg
        }
    }
    return nil
}

enum DeviceType {
    case ios
    case android
    case unknown
}

func detectDeviceType(_ deviceId: String) -> DeviceType {
    // iOS Simulator UDIDs are in UUID format: 8-4-4-4-12 hex characters
    let uuidPattern = "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"
    if let regex = try? NSRegularExpression(pattern: uuidPattern),
       regex.firstMatch(in: deviceId, range: NSRange(deviceId.startIndex..., in: deviceId)) != nil {
        return .ios
    }

    // Android device IDs: emulators, network devices, USB serials
    // Emulator format: emulator-5554
    if deviceId.hasPrefix("emulator-") {
        return .android
    }

    // Network device format: 192.168.x.x:5555
    let ipPortPattern = "^\\d+\\.\\d+\\.\\d+\\.\\d+:\\d+$"
    if let regex = try? NSRegularExpression(pattern: ipPortPattern),
       regex.firstMatch(in: deviceId, range: NSRange(deviceId.startIndex..., in: deviceId)) != nil {
        return .android
    }

    // USB device serials are typically alphanumeric, 6-20 chars
    // But we can't be certain, so return unknown and let validation decide
    return .unknown
}

func validateiOSDevice(_ udid: String) -> Bool {
    let result = Shell.runCommand("/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "booted", "-j"], suppressStderr: true)
    guard result.succeeded,
          let data = result.stdout.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let devices = json["devices"] as? [String: [[String: Any]]] else {
        return false
    }
    for deviceList in devices.values {
        if deviceList.contains(where: {
            ($0["udid"] as? String) == udid && ($0["state"] as? String) == "Booted"
        }) {
            return true
        }
    }
    return false
}

func validateAndroidDevice(_ deviceId: String) -> Bool {
    let devices = AndroidEmulatorHelper.getRunningDevices()
    return devices.contains(deviceId)
}

func validateDevice(_ deviceId: String, type: DeviceType) -> Bool {
    switch type {
    case .ios:
        return validateiOSDevice(deviceId)
    case .android:
        return validateAndroidDevice(deviceId)
    case .unknown:
        return validateAndroidDevice(deviceId) || validateiOSDevice(deviceId)
    }
}

func printDeviceNotFoundError(_ deviceId: String) {
    printError("Device '\(deviceId)' not found or not running.")
    let androidDevices = AndroidEmulatorHelper.getRunningDevices()
    if !androidDevices.isEmpty {
        printInfo("\nAvailable Android devices:")
        for device in androidDevices {
            let name = AndroidEmulatorHelper.getDeviceFriendlyName(device)
            printInfo("\t\(device) - \(name)")
        }
    }
    if let iosUDID = SimulatorHelper.getBootedSimulator() {
        printInfo("\nAvailable iOS Simulator:")
        printInfo("\t\(iosUDID)")
    }
}

func openUrlOnDevice(_ urlString: String, deviceId: String) -> Bool {
    var deviceType = detectDeviceType(deviceId)
    var alreadyValidated = false

    // For unknown type, try to determine by validation
    if deviceType == .unknown {
        if validateAndroidDevice(deviceId) {
            deviceType = .android
            alreadyValidated = true
        } else if validateiOSDevice(deviceId) {
            deviceType = .ios
            alreadyValidated = true
        } else {
            // Device not found on either platform
            printDeviceNotFoundError(deviceId)
            return false
        }
    }

    // Validate device exists (only for known types that weren't validated above)
    if !alreadyValidated && !validateDevice(deviceId, type: deviceType) {
        printDeviceNotFoundError(deviceId)
        return false
    }

    switch deviceType {
    case .ios:
        return SimulatorHelper.openUrl(urlString, udid: deviceId)
    case .android:
        return AndroidEmulatorHelper.openUrl(urlString, deviceId: deviceId, validated: true)
    case .unknown:
        // This case is unreachable since we handle .unknown above
        return false
    }
}

enum DeviceMemory {
    static var lastChoice: String? = nil
    static var shouldUseLast = false
}

func openUrlInAvailableEmulator(_ urlString: String) {
    let iOSSimulatorAvailable = SimulatorHelper.getBootedSimulator() != nil
    let androidDevices = AndroidEmulatorHelper.getRunningDevices()

    var availableOptions: [(String, String)] = []  // (display name, action type)

    // Add iOS Simulator if available
    if iOSSimulatorAvailable {
        availableOptions.append(("📱 iOS Simulator", "ios"))
    }

    // Add Android devices with friendly names
    for device in androidDevices {
        let friendlyName = AndroidEmulatorHelper.getDeviceFriendlyName(device)
        availableOptions.append(("📱 \(friendlyName)", "android:\(device)"))
    }

    // Add local computer option
    availableOptions.append(("💻 Open on this computer", "local"))
    availableOptions.append(("⏭️ Skip (don't open)", "skip"))

    if availableOptions.isEmpty {
        printError("No devices available.")
        return
    }

    let selectedAction: String

    // Check if we should use the last device and it's still available
    if DeviceMemory.shouldUseLast, let lastChoice = DeviceMemory.lastChoice,
       let lastIndex: Array<(String, String)>.Index = availableOptions.firstIndex(where: { $0.1 == lastChoice }) {
        selectedAction = lastChoice
        printInfo("🔄 Using previous device: \(availableOptions[lastIndex].0)")
    } else {
        printInfo("\n📱 Choose target device:")
        for (index, option) in availableOptions.enumerated() {
            printInfo("\t\(index + 1)) \(option.0)")
        }

        // Show quick repeat hint if we have a previous choice
        if let lastChoice = DeviceMemory.lastChoice,
           let lastIndex = availableOptions.firstIndex(where: { $0.1 == lastChoice }) {
            printInfo("\n💡 Press 'r' to use previous device (\(availableOptions[lastIndex].0))")
        }
        print("")

        guard let input = readLine() else {
            printError("Invalid input. Not opening URL.")
            return
        }

        // Handle repeat option
        if input.lowercased() == "r", let lastChoice = DeviceMemory.lastChoice,
           availableOptions.contains(where: { $0.1 == lastChoice }) {
            selectedAction = lastChoice
            DeviceMemory.shouldUseLast = true
        } else if let choice = Int(input), choice >= 1 && choice <= availableOptions.count {
            selectedAction = availableOptions[choice - 1].1
            DeviceMemory.lastChoice = selectedAction
        } else {
            printError("Invalid choice. Not opening URL.")
            return
        }
    }

    // Execute the selected action
    if selectedAction == "ios" {
        SimulatorHelper.openUrl(urlString)
    } else if selectedAction.starts(with: "android:") {
        let deviceId = String(selectedAction.dropFirst("android:".count))
        AndroidEmulatorHelper.openUrl(urlString, deviceId: deviceId)
    } else if selectedAction == "local" {
        print("💻 Opening on this computer…")
        let result = Shell.runCommand("/usr/bin/open", arguments: [urlString])
        if result.succeeded {
            printSuccess("Opened URL: \(urlString)")
        } else {
            printError("Error opening URL: \(result.stderr)")
        }
    } else if selectedAction == "skip" {
        printInfo("⏭️  Skipped")
    }
}

@main
struct QRGoMain {
    static func printHelp() {
        print("""
        QRGo - QR Code reader for iOS Simulator and Android Emulator

        Usage: qrgo [options]

        Options:
          -d, --device <id>      Target a specific device by ID (skips device selection)
                                 Android: emulator-5554, 192.168.1.100:5555, or USB serial
                                 iOS: Simulator UDID (e.g., A1B2C3D4-E5F6-7890-ABCD-...)
          -t, --transform-urls   Transform specific URLs to use custom URL schemes
                                 (e.g., cash.app URLs to cashme:// scheme)
          -c, --copy             Copy the parsed URL to clipboard
          -v, --version          Show the installed version
          -h, --help             Show this help message
        """)
        exit(0)
    }

    static func printVersion() {
        let result = Shell.runLoginShell("brew info --json=v2 block/tap/qrgo | jq -r '.formulae[0].installed[0].version'")
        if result.succeeded, !result.trimmedOutput.isEmpty, result.trimmedOutput != "null" {
            printSuccess("qrgo \(result.trimmedOutput)")
        } else {
            printError("Could not determine installed version. Is qrgo installed via Homebrew?")
            exit(1)
        }
        exit(0)
    }
    
    static func main() async {
        // Parse command line arguments
        if CommandLine.arguments.contains("--help") || CommandLine.arguments.contains("-h") {
            printHelp()
        }
        if CommandLine.arguments.contains("--version") || CommandLine.arguments.contains("-v") {
            printVersion()
        }
        
        let shouldTransformUrls = CommandLine.arguments.contains("--transform-urls") ||
                                CommandLine.arguments.contains("-t")
        let copyToClipboard = CommandLine.arguments.contains("--copy") ||
                                   CommandLine.arguments.contains("-c")
        let targetDevice = parseDeviceArgument()

        // Validate target device exists before doing anything else
        if let deviceId = targetDevice {
            let deviceType = detectDeviceType(deviceId)
            if !validateDevice(deviceId, type: deviceType) {
                printDeviceNotFoundError(deviceId)
                exit(1)
            }
        }

        guard #available(macOS 12.3, *) else {
            printError("This application requires macOS 12.3 or later.")
            exit(1)
        }

        let hasPermission = await ScreenCapturePermissionHelper.checkScreenCapturePermission()
        
        if !hasPermission {
            printInfo("Screen Recording permission is required for this application.")
            printInfo("Opening System Settings to enable Screen Recording permission…")
            ScreenCapturePermissionHelper.requestScreenCapturePermission()
            exit(1)
        }

        printWarning("Please select the area containing the QR code…")

        do {
            if let imagePath = try ScreenCaptureHelper.captureSelection() {
                printSuccess("Image saved to: \(imagePath)")
                let decodedStrings = QRCodeDecoder.decode(imagePath: imagePath)

                if decodedStrings.isEmpty {
                    printError("No QR codes found in the selected area.")
                } else {
                    for (index, string) in decodedStrings.enumerated() {
                        if !copyToClipboard {
                            printInfo("Decoded QR code \(index + 1): \(string)")
                        }

                        // Try to open the URL in available emulator
                        if string.lowercased().starts(with: "http://") ||
                           string.lowercased().starts(with: "https://") ||
                           string.lowercased().starts(with: "cashme://") {
                            let urlToOpen = shouldTransformUrls ? transformUrl(string) : string
                            if shouldTransformUrls && urlToOpen != string {
                                printInfo("Transformed URL: \(urlToOpen)")
                            }
                            if copyToClipboard {
                                copyUrlToClipboard(urlToOpen)
                            } else if let deviceId = targetDevice {
                                if !openUrlOnDevice(urlToOpen, deviceId: deviceId) {
                                    exit(1)
                                }
                            } else {
                                openUrlInAvailableEmulator(urlToOpen)
                            }
                        } else {
                            printError("Not opening in emulator - URL doesn't start with http://, https://, or cashme://")
                        }
                    }
                }

                // Clean up temporary image file
                try? FileManager.default.removeItem(atPath: imagePath)
            } else {
                printError("Screen capture cancelled.")
            }
        } catch {
            printError("Screen capture failed: \(error.localizedDescription)")
            exit(1)
        }
    }
}
