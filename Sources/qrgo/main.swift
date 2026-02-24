import Foundation
import AppKit
import CoreImage
import Vision
import ScreenCaptureKit

// ANSI color codes for terminal output
enum Colors {
    static let red = "\u{001B}[31m"
    static let green = "\u{001B}[32m"
    static let yellow = "\u{001B}[33m"
    static let reset = "\u{001B}[0m"
}

@available(macOS 12.3, *)
class ScreenCapturePermissionHelper {
    static func checkScreenCapturePermission() async -> Bool {
        do {
            _ = try await SCShareableContent.current
            return true
        } catch {
            return false
        }
    }
    
    static func requestScreenCapturePermission() {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"]
        
        do {
            try task.run()
            task.waitUntilExit()
            print("Please enable Screen Recording permission in System Settings and restart the application.")
        } catch {
            print("Error opening System Settings: \(error)")
        }
    }
}

class SimulatorHelper {
    static func getBootedSimulator() -> String? {
        let task = Process()
        let pipe = Pipe()
        
        task.launchPath = "/usr/bin/xcrun"
        task.arguments = ["simctl", "list", "devices", "booted", "-j"]
        task.standardOutput = pipe
        
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let devices = json["devices"] as? [String: [[String: Any]]] {
                for deviceList in devices.values {
                    if let device = deviceList.first(where: { ($0["state"] as? String) == "Booted" }),
                       let udid = device["udid"] as? String {
                        return udid
                    }
                }
            }
        } catch {
            print("Error getting simulator: \(error)")
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
                print("No booted iOS Simulator found")
                return false
            }
            simulatorUDID = bootedUDID
        }

        let task = Process()
        let pipe = Pipe()
        task.launchPath = "/usr/bin/xcrun"
        task.arguments = ["simctl", "openurl", simulatorUDID, urlString]
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                print("")  // blank line before success
                print("Opened URL on \(Colors.green)iOS Simulator\(Colors.reset)")
                return true
            } else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                print("")  // blank line before error
                print("\(Colors.red)Error:\(Colors.reset) Failed to open URL in iOS Simulator")
                if !output.isEmpty {
                    print(output.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                return false
            }
        } catch {
            print("")
            print("\(Colors.red)Error:\(Colors.reset) \(error)")
            return false
        }
    }
}

class AndroidEmulatorHelper {
    // Cache adb path to avoid repeated shell lookups
    private static var _cachedAdbPath: String? = nil
    private static var _adbPathChecked = false

    static func findAdbPath() -> String? {
        if _adbPathChecked {
            return _cachedAdbPath
        }

        // Find adb using the user's login shell to get their full PATH
        let task = Process()
        let pipe = Pipe()

        task.launchPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/sh"
        task.arguments = ["-l", "-c", "which adb"]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()

            if task.terminationStatus == 0,
               let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty {
                _cachedAdbPath = output
            }
        } catch {
            // Return nil if shell fails
        }

        _adbPathChecked = true
        return _cachedAdbPath
    }
    
    static func getRunningDevices() -> [String] {
        guard let adbPath = findAdbPath() else {
            print("adb not found. Please install Android SDK or ensure adb is in your PATH.")
            return []
        }

        let task = Process()
        let pipe = Pipe()

        task.launchPath = adbPath
        task.arguments = ["devices"]
        task.standardOutput = pipe

        var devices: [String] = []

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()

            if let output = String(data: data, encoding: .utf8) {
                // Parse adb devices output - get ALL connected devices, not just emulators
                let lines = output.components(separatedBy: .newlines)
                for line in lines {
                    let components = line.components(separatedBy: .whitespaces)
                    if components.count >= 2 && components[1] == "device" {
                        devices.append(components[0])
                    }
                }
            }
        } catch {
            print("Error getting Android devices: \(error)")
        }
        return devices
    }

    // Legacy method for backward compatibility
    static func getRunningEmulators() -> [String] {
        return getRunningDevices().filter { $0.contains("emulator-") }
    }

    static func getDeviceFriendlyName(_ deviceId: String) -> String {
        guard let adbPath = findAdbPath() else {
            return "Android Device (\(deviceId))"
        }

        // Get all device properties in a single adb call
        let props = getDeviceProperties(deviceId: deviceId, adbPath: adbPath)
        let model = props["ro.product.model"] ?? ""
        let manufacturer = props["ro.product.manufacturer"] ?? ""
        let apiLevel = props["ro.build.version.sdk"] ?? ""
        let isQemu = props["ro.kernel.qemu"] ?? ""
        let avdName = props["ro.boot.qemu.avd_name"] ?? ""

        // Check if it's an emulator
        let isEmulator = isQemu == "1" || deviceId.contains("emulator-")

        var displayName = ""

        if isEmulator {
            if !avdName.isEmpty {
                // Clean up AVD name to make it more readable
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
            // Real device
            if !manufacturer.isEmpty && !model.isEmpty {
                // Avoid redundancy (e.g., "Samsung Samsung Galaxy S21")
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

    // Fetch multiple device properties in a single adb shell call
    private static func getDeviceProperties(deviceId: String, adbPath: String) -> [String: String] {
        let properties = [
            "ro.product.model",
            "ro.product.manufacturer",
            "ro.build.version.sdk",
            "ro.kernel.qemu",
            "ro.boot.qemu.avd_name"
        ]

        let task = Process()
        let pipe = Pipe()

        // Build a shell command that outputs all properties with a delimiter
        let shellCommand = properties.map { "getprop \($0)" }.joined(separator: " && echo '|||' && ")
        task.launchPath = adbPath
        task.arguments = ["-s", deviceId, "shell", shellCommand]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        var result: [String: String] = [:]

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()

            if task.terminationStatus == 0,
               let output = String(data: data, encoding: .utf8) {
                let values = output.components(separatedBy: "|||").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                for (index, prop) in properties.enumerated() where index < values.count {
                    result[prop] = values[index]
                }
            }
        } catch {
            // Return empty dict on error
        }

        return result
    }

    @discardableResult
    static func openUrl(_ urlString: String, deviceId: String? = nil, validated: Bool = false) -> Bool {
        guard let adbPath = findAdbPath() else {
            print("adb not found. Please install Android SDK or ensure adb is in your PATH.")
            return false
        }

        let targetDevice: String
        if let deviceId = deviceId, validated {
            // Skip validation if already validated by caller
            targetDevice = deviceId
        } else {
            let devices = getRunningDevices()
            guard !devices.isEmpty else {
                print("No running Android devices found")
                return false
            }

            if let deviceId = deviceId, devices.contains(deviceId) {
                targetDevice = deviceId
            } else {
                // Use first device if no specific device provided
                targetDevice = devices[0]
            }
        }

        let task = Process()
        let pipe = Pipe()
        task.launchPath = adbPath
        task.arguments = ["-s", targetDevice, "shell", "am", "start", "-a", "android.intent.action.VIEW", "-c", "android.intent.category.BROWSABLE", "-d", urlString]
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let deviceName = getDeviceFriendlyName(targetDevice)

            // Check both exit status and output for errors
            if task.terminationStatus != 0 || output.contains("Error:") {
                print("")  // blank line before error
                if output.contains("unable to resolve Intent") {
                    print("\(Colors.red)Error:\(Colors.reset) No app on \(Colors.yellow)\(deviceName)\(Colors.reset) can handle this URL.")
                } else {
                    print("\(Colors.red)Error:\(Colors.reset) Failed to open URL on \(Colors.yellow)\(deviceName)\(Colors.reset)")
                    if !output.isEmpty {
                        print(output.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
                return false
            } else {
                print("")  // blank line before success
                print("Opened URL on \(Colors.green)\(deviceName)\(Colors.reset)")
                return true
            }
        } catch {
            print("Error opening URL in Android device: \(error)")
            return false
        }
    }
}

class ScreenCaptureHelper {
    static func captureSelection() -> String? {
        let tempDir = FileManager.default.temporaryDirectory
        let timestamp = Int(Date().timeIntervalSince1970)
        let imagePath = tempDir.appendingPathComponent("qr_capture_\(timestamp).png").path
        
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        task.arguments = ["-i", imagePath] // -i for interactive
        
        task.launch()
        task.waitUntilExit()
        
        // Check if file exists
        return FileManager.default.fileExists(atPath: imagePath) ? imagePath : nil
    }
}

class QRCodeDecoder {
    static func decode(imagePath: String) -> [String] {
        guard let image = NSImage(contentsOfFile: imagePath),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }
        
        let request = VNDetectBarcodesRequest()
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        do {
            try requestHandler.perform([request])
            guard let results = request.results else { return [] }
            
            return results.compactMap { result in
                guard let barcode = result as? VNBarcodeObservation,
                      let payload = barcode.payloadStringValue else {
                    return nil
                }
                return payload
            }
        } catch {
            print("Failed to detect QR codes: \(error)")
            return []
        }
    }
}

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
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
    let pipe = Pipe()
    process.standardInput = pipe

    do {
        try process.run()
        pipe.fileHandleForWriting.write(text.data(using: .utf8)!)
        pipe.fileHandleForWriting.closeFile()
        process.waitUntilExit()
        print("📋 Copied to clipboard: \(text)")
    } catch {
        print("Failed to copy to clipboard: \(error)")
    }
}

func parseDeviceArgument() -> String? {
    let args = CommandLine.arguments
    for (index, arg) in args.enumerated() {
        if (arg == "-d" || arg == "--device") && index + 1 < args.count {
            let nextArg = args[index + 1]
            // Ensure the next argument is not another flag
            if nextArg.hasPrefix("-") {
                print("Error: -d/--device requires a device ID, not '\(nextArg)'")
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
    let task = Process()
    let pipe = Pipe()

    task.launchPath = "/usr/bin/xcrun"
    task.arguments = ["simctl", "list", "devices", "booted", "-j"]
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice

    do {
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let devices = json["devices"] as? [String: [[String: Any]]] {
            for deviceList in devices.values {
                if deviceList.contains(where: {
                    ($0["udid"] as? String) == udid && ($0["state"] as? String) == "Booted"
                }) {
                    return true
                }
            }
        }
    } catch {
        // Validation failed
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
    print("\(Colors.red)Error:\(Colors.reset) Device '\(Colors.yellow)\(deviceId)\(Colors.reset)' not found or not running.")
    let androidDevices = AndroidEmulatorHelper.getRunningDevices()
    if !androidDevices.isEmpty {
        print("\nAvailable Android devices:")
        for device in androidDevices {
            let name = AndroidEmulatorHelper.getDeviceFriendlyName(device)
            print("  \(device) - \(name)")
        }
    }
    if let iosUDID = SimulatorHelper.getBootedSimulator() {
        print("\nAvailable iOS Simulator:")
        print("  \(iosUDID)")
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

// Global variables for device choice memory
var lastDeviceChoice: String? = nil
var shouldUseLastDevice = false

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
    availableOptions.append(("⏭️  Skip (don't open)", "skip"))

    if availableOptions.isEmpty {
        print("No devices available")
        return
    }

    let selectedAction: String

    // Check if we should use the last device and it's still available
    if shouldUseLastDevice, let lastChoice = lastDeviceChoice,
       let lastIndex = availableOptions.firstIndex(where: { $0.1 == lastChoice }) {
        selectedAction = lastChoice
        print("🔄 Using previous device: \(availableOptions[lastIndex].0)")
    } else {
        print("\n📱 Choose target device:")
        for (index, option) in availableOptions.enumerated() {
            print("   \(index + 1)) \(option.0)")
        }

        // Show quick repeat hint if we have a previous choice
        if let lastChoice = lastDeviceChoice,
           let lastIndex = availableOptions.firstIndex(where: { $0.1 == lastChoice }) {
            print("\n💡 Press 'r' to use previous device (\(availableOptions[lastIndex].0))")
        }
        print("")

        guard let input = readLine() else {
            print("Invalid input. Not opening URL.")
            return
        }

        // Handle repeat option
        if input.lowercased() == "r", let lastChoice = lastDeviceChoice,
           availableOptions.contains(where: { $0.1 == lastChoice }) {
            selectedAction = lastChoice
            shouldUseLastDevice = true
        } else if let choice = Int(input), choice >= 1 && choice <= availableOptions.count {
            selectedAction = availableOptions[choice - 1].1
            lastDeviceChoice = selectedAction  // Remember this choice
        } else {
            print("Invalid choice. Not opening URL.")
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
        print("💻 Opening on this computer...")
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [urlString]

        do {
            try task.run()
            task.waitUntilExit()
            print("Opened URL: \(urlString)")
        } catch {
            print("Error opening URL: \(error)")
        }
    } else if selectedAction == "skip" {
        print("⏭️  Skipped")
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
        let task = Process()
        let pipe = Pipe()
        let errPipe = Pipe()

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/sh"
        task.launchPath = shell
        task.arguments = ["-l", "-c", "brew info --json=v2 block/tap/qrgo | jq -r '.formulae[0].installed[0].version'"]
        task.standardOutput = pipe
        task.standardError = errPipe

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()

            if task.terminationStatus == 0,
               let version = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !version.isEmpty, version != "null" {
                print("\(Colors.green)qrgo v\(version)\(Colors.reset)")
            } else {
                print("\(Colors.red)Error:\(Colors.reset) Could not determine installed version. Is qrgo installed via Homebrew?")
                exit(1)
            }
        } catch {
            print("\(Colors.red)Error:\(Colors.reset) \(error)")
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
            print("This application requires macOS 12.3 or later.")
            exit(1)
        }

        let hasPermission = await ScreenCapturePermissionHelper.checkScreenCapturePermission()
        
        if !hasPermission {
            print("Screen Recording permission is required for this application.")
            print("Opening System Settings to enable Screen Recording permission...")
            ScreenCapturePermissionHelper.requestScreenCapturePermission()
            exit(1)
        }

        print("Please select the area containing the QR code...")

        if let imagePath = ScreenCaptureHelper.captureSelection() {
            print("Image saved to: \(imagePath)")
            let decodedStrings = QRCodeDecoder.decode(imagePath: imagePath)
            
            if decodedStrings.isEmpty {
                print("No QR codes found in the selected area.")
            } else {
                for (index, string) in decodedStrings.enumerated() {
                    if !copyToClipboard {
                        print("Decoded QR code \(index + 1): \(string)")
                    }
                    
                    // Try to open the URL in available emulator
                    if string.lowercased().starts(with: "http://") || 
                       string.lowercased().starts(with: "https://") ||
                       string.lowercased().starts(with: "cashme://") {
                        let urlToOpen = shouldTransformUrls ? transformUrl(string) : string
                        if shouldTransformUrls && urlToOpen != string {
                            print("Transformed URL: \(urlToOpen)")
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
                        print("Not opening in emulator - URL doesn't start with http://, https://, or cashme://")
                    }
                }
            }

            // Clean up temporary image file
            try? FileManager.default.removeItem(atPath: imagePath)
        } else {
            print("Screen capture cancelled.")
        }
    }
}
