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

private struct ShellResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { exitCode == 0 }

    var trimmedOutput: String {
        stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@discardableResult
private func runCommand(
    _ executable: String,
    arguments: [String] = [],
    mergeStderr: Bool = false,
    suppressStderr: Bool = false,
    input: String? = nil
) -> ShellResult {
    let task = Process()
    let stdoutPipe = Pipe()

    task.launchPath = executable
    task.arguments = arguments
    task.standardOutput = stdoutPipe

    var stderrPipe: Pipe? = nil
    if mergeStderr {
        task.standardError = stdoutPipe
    } else if suppressStderr {
        task.standardError = FileHandle.nullDevice
    } else {
        let pipe = Pipe()
        task.standardError = pipe
        stderrPipe = pipe
    }

    var inputPipe: Pipe? = nil
    if input != nil {
        let pipe = Pipe()
        task.standardInput = pipe
        inputPipe = pipe
    }

    do {
        try task.run()

        if let inputData = input?.data(using: .utf8) {
            inputPipe?.fileHandleForWriting.write(inputData)
            inputPipe?.fileHandleForWriting.closeFile()
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe?.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        return ShellResult(
            exitCode: task.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: stderrData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        )
    } catch {
        return ShellResult(exitCode: -1, stdout: "", stderr: error.localizedDescription)
    }
}

/// Runs a command string via the user's login shell (inherits full PATH).
private func runLoginShell(_ command: String) -> ShellResult {
    let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/sh"
    return runCommand(shell, arguments: ["-l", "-c", command], suppressStderr: true)
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
        let result = runCommand("/usr/bin/open", arguments: ["x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"])
        if result.succeeded {
            print("Please enable Screen Recording permission in System Settings and restart the application.")
        } else {
            print("Error opening System Settings: \(result.stderr)")
        }
    }
}

class SimulatorHelper {
    static func getBootedSimulator() -> String? {
        let result = runCommand("/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "booted", "-j"])
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
                print("No booted iOS Simulator found")
                return false
            }
            simulatorUDID = bootedUDID
        }

        let result = runCommand("/usr/bin/xcrun", arguments: ["simctl", "openurl", simulatorUDID, urlString], mergeStderr: true)
        print("")
        if result.succeeded {
            print("Opened URL on \(Colors.green)iOS Simulator\(Colors.reset)")
            return true
        } else {
            print("\(Colors.red)Error:\(Colors.reset) Failed to open URL in iOS Simulator")
            if !result.trimmedOutput.isEmpty {
                print(result.trimmedOutput)
            }
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

        let result = runLoginShell("which adb")
        if result.succeeded, !result.trimmedOutput.isEmpty {
            _cachedAdbPath = result.trimmedOutput
        }

        _adbPathChecked = true
        return _cachedAdbPath
    }
    
    static func getRunningDevices() -> [String] {
        guard let adbPath = findAdbPath() else {
            print("adb not found. Please install Android SDK or ensure adb is in your PATH.")
            return []
        }

        let result = runCommand(adbPath, arguments: ["devices"])
        guard result.succeeded else { return [] }

        // Parse adb devices output - get ALL connected devices, not just emulators
        return result.stdout.components(separatedBy: .newlines).compactMap { line in
            let components = line.components(separatedBy: .whitespaces)
            return (components.count >= 2 && components[1] == "device") ? components[0] : nil
        }
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

    private static func getDeviceProperties(deviceId: String, adbPath: String) -> [String: String] {
        let properties = [
            "ro.product.model",
            "ro.product.manufacturer",
            "ro.build.version.sdk",
            "ro.kernel.qemu",
            "ro.boot.qemu.avd_name"
        ]

        let shellCommand = properties.map { "getprop \($0)" }.joined(separator: " && echo '|||' && ")
        let result = runCommand(adbPath, arguments: ["-s", deviceId, "shell", shellCommand], suppressStderr: true)
        guard result.succeeded else { return [:] }

        var props: [String: String] = [:]
        let values = result.stdout.components(separatedBy: "|||").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        for (index, prop) in properties.enumerated() where index < values.count {
            props[prop] = values[index]
        }
        return props
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

        let result = runCommand(
            adbPath,
            arguments: ["-s", targetDevice, "shell", "am", "start", "-a", "android.intent.action.VIEW", "-c", "android.intent.category.BROWSABLE", "-d", urlString],
            mergeStderr: true
        )
        let deviceName = getDeviceFriendlyName(targetDevice)

        // Check both exit status and output for errors
        if !result.succeeded || result.stdout.contains("Error:") {
            print("")
            if result.stdout.contains("unable to resolve Intent") {
                print("\(Colors.red)Error:\(Colors.reset) No app on \(Colors.yellow)\(deviceName)\(Colors.reset) can handle this URL.")
            } else {
                print("\(Colors.red)Error:\(Colors.reset) Failed to open URL on \(Colors.yellow)\(deviceName)\(Colors.reset)")
                if !result.trimmedOutput.isEmpty {
                    print(result.trimmedOutput)
                }
            }
            return false
        } else {
            print("")
            print("Opened URL on \(Colors.green)\(deviceName)\(Colors.reset)")
            return true
        }
    }
}

class ScreenCaptureHelper {
    static func captureSelection() -> String? {
        let tempDir = FileManager.default.temporaryDirectory
        let timestamp = Int(Date().timeIntervalSince1970)
        let imagePath = tempDir.appendingPathComponent("qr_capture_\(timestamp).png").path

        runCommand("/usr/sbin/screencapture", arguments: ["-i", imagePath])
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
            
            return results.compactMap { $0.payloadStringValue }
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
    let result = runCommand("/usr/bin/pbcopy", input: text)
    if result.succeeded {
        print("📋 Copied to clipboard: \(text)")
    } else {
        print("Failed to copy to clipboard: \(result.stderr)")
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
    let result = runCommand("/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "booted", "-j"], suppressStderr: true)
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
        let result = runCommand("/usr/bin/open", arguments: [urlString])
        if result.succeeded {
            print("Opened URL: \(urlString)")
        } else {
            print("Error opening URL: \(result.stderr)")
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
        let result = runLoginShell("brew info --json=v2 block/tap/qrgo | jq -r '.formulae[0].installed[0].version'")
        if result.succeeded, !result.trimmedOutput.isEmpty, result.trimmedOutput != "null" {
            print("qrgo \(result.trimmedOutput)")
        } else {
            print("\(Colors.red)Error:\(Colors.reset) Could not determine installed version. Is qrgo installed via Homebrew?")
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
