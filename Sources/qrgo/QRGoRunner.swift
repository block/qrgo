import Foundation
import ScreenCaptureKit

struct QRGoRunConfiguration {
    let shouldTransformUrls: Bool
    let copyToClipboard: Bool
    let targetDevice: String?
    let showsCapturePath: Bool
    let showsSelectionPrompt: Bool
    let showsCopyTargetOption: Bool
}

enum DeviceType {
    case ios
    case android
    case unknown
}

enum TargetAction: Equatable {
    case ios
    case android(deviceId: String)
    case copy
    case local
    case skip

    var key: String {
        switch self {
        case .ios:
            return "ios"
        case .android(let deviceId):
            return "android:\(deviceId)"
        case .copy:
            return "copy"
        case .local:
            return "local"
        case .skip:
            return "skip"
        }
    }
}

struct TargetOption {
    let displayName: String
    let action: TargetAction
}

@MainActor
protocol QRGoTargetSelecting {
    func selectTarget(for urlString: String, from options: [TargetOption]) -> TargetAction?
}

@MainActor
protocol QRGoNotifying {
    /// Whether the runner should surface URL open results outside the opener helpers.
    var reportsDeviceOpenResults: Bool { get }

    func error(_ message: String)
    func info(_ message: String)
    func success(_ message: String)
    func warning(_ message: String)
}

struct TerminalNotifier: QRGoNotifying {
    let reportsDeviceOpenResults = false

    func error(_ message: String) {
        printError(message)
    }

    func info(_ message: String) {
        printInfo(message)
    }

    func success(_ message: String) {
        printSuccess(message)
    }

    func warning(_ message: String) {
        printWarning(message)
    }
}

struct TerminalTargetSelector: QRGoTargetSelecting {
    func selectTarget(for urlString: String, from options: [TargetOption]) -> TargetAction? {
        let selectedAction: TargetAction

        if DeviceMemory.shouldUseLast,
           let lastChoice = DeviceMemory.lastChoice,
           let lastIndex = options.firstIndex(where: { $0.action.key == lastChoice }) {
            selectedAction = options[lastIndex].action
            printInfo("🔄 Using previous device: \(options[lastIndex].displayName)")
        } else {
            printInfo("\n📱 Choose target device:")
            for (index, option) in options.enumerated() {
                printInfo("\t\(index + 1)) \(option.displayName)")
            }

            if let lastChoice = DeviceMemory.lastChoice,
               let lastIndex = options.firstIndex(where: { $0.action.key == lastChoice }) {
                printInfo("\n💡 Press 'r' to use previous device (\(options[lastIndex].displayName))")
            }
            print("")

            guard let input = readLine() else {
                printError("Invalid input. Not opening URL.")
                return nil
            }

            if input.lowercased() == "r",
               let lastChoice = DeviceMemory.lastChoice,
               let lastOption = options.first(where: { $0.action.key == lastChoice }) {
                selectedAction = lastOption.action
                DeviceMemory.shouldUseLast = true
            } else if let choice = Int(input), choice >= 1 && choice <= options.count {
                selectedAction = options[choice - 1].action
                DeviceMemory.lastChoice = selectedAction.key
            } else {
                printError("Invalid choice. Not opening URL.")
                return nil
            }
        }

        return selectedAction
    }
}

@MainActor
struct QRGoRunner {
    let configuration: QRGoRunConfiguration
    let targetSelector: QRGoTargetSelecting
    let notifier: QRGoNotifying

    func openLastScan() async -> Bool {
        guard let urlString = LastScanStore.lastScannedURL else {
            notifier.warning("No QR code has been scanned yet.")
            return false
        }
        guard isSupportedUrl(urlString) else {
            notifier.error("The last scanned QR code is not a supported URL.")
            return false
        }
        if let deviceId = configuration.targetDevice,
           !validateConfiguredDevice(deviceId) {
            return false
        }

        notifier.info("Last scanned QR code: \(urlString)")
        let urlToOpen = configuration.shouldTransformUrls ? transformUrl(urlString) : urlString
        if configuration.shouldTransformUrls && urlToOpen != urlString {
            notifier.info("Transformed URL: \(urlToOpen)")
        }
        if let deviceId = configuration.targetDevice {
            return openUrlOnConfiguredDevice(urlToOpen, deviceId: deviceId)
        }
        return openUrlInAvailableTarget(urlToOpen)
    }

    func run() async -> Bool {
        if let deviceId = configuration.targetDevice,
           !validateConfiguredDevice(deviceId) {
            return false
        }

        guard #available(macOS 12.3, *) else {
            notifier.error("This application requires macOS 12.3 or later.")
            return false
        }

        let hasPermission = await ScreenCapturePermissionHelper.checkScreenCapturePermission()
        if !hasPermission {
            notifier.warning(
                "Screen Recording permission is required for this application. " +
                    "System Settings will open so you can enable it."
            )
            ScreenCapturePermissionHelper.requestScreenCapturePermission()
            return false
        }

        if configuration.showsSelectionPrompt {
            notifier.warning("Please select the area containing the QR code…")
        }

        do {
            guard let imagePath = try ScreenCaptureHelper.captureSelection() else {
                notifier.info("Screen capture canceled.")
                return true
            }
            defer {
                try? FileManager.default.removeItem(atPath: imagePath)
            }

            if configuration.showsCapturePath {
                notifier.success("Image saved to: \(imagePath)")
            }

            let decodedStrings = QRCodeDecoder.decode(imagePath: imagePath)
            if decodedStrings.isEmpty {
                notifier.error("No QR codes found in the selected area.")
                return true
            }

            var succeeded = true
            for (index, string) in decodedStrings.enumerated() {
                if !configuration.copyToClipboard {
                    notifier.info("Decoded QR code \(index + 1): \(string)")
                }

                guard isSupportedUrl(string) else {
                    notifier.error("Not opening in emulator - URL doesn't start with http://, https://, or cashme://")
                    continue
                }
                saveLastScan(string)

                let urlToOpen = configuration.shouldTransformUrls ? transformUrl(string) : string
                if configuration.shouldTransformUrls && urlToOpen != string {
                    notifier.info("Transformed URL: \(urlToOpen)")
                }

                if configuration.copyToClipboard {
                    let copied = copyUrlToClipboard(urlToOpen)
                    if notifier.reportsDeviceOpenResults {
                        if copied {
                            notifier.success("Copied URL to clipboard.")
                        } else {
                            notifier.error("Failed to copy URL to clipboard.")
                        }
                    }
                } else if let deviceId = configuration.targetDevice {
                    let opened = openUrlOnConfiguredDevice(urlToOpen, deviceId: deviceId)
                    if !opened {
                        succeeded = false
                    }
                } else {
                    _ = openUrlInAvailableTarget(urlToOpen)
                }
            }
            return succeeded
        } catch {
            notifier.error("Screen capture failed: \(error.localizedDescription)")
            return false
        }
    }

    private func openUrlInAvailableTarget(_ urlString: String) -> Bool {
        let options = makeAvailableTargetOptions(includesCopyOption: configuration.showsCopyTargetOption)
        guard let selectedAction = targetSelector.selectTarget(for: urlString, from: options) else {
            return false
        }

        let opened = openUrl(urlString, action: selectedAction)
        if notifier.reportsDeviceOpenResults {
            reportOpenResult(opened, for: selectedAction)
        }
        return opened
    }

    private func openUrlOnConfiguredDevice(_ urlString: String, deviceId: String) -> Bool {
        let opened = openUrlOnDevice(urlString, deviceId: deviceId)
        if notifier.reportsDeviceOpenResults {
            reportOpenResult(opened, for: targetAction(for: deviceId))
        }
        return opened
    }

    private func saveLastScan(_ urlString: String) {
        if !LastScanStore.save(urlString) {
            notifier.warning("Could not save this QR code as the last scan.")
        }
    }

    private func validateConfiguredDevice(_ deviceId: String) -> Bool {
        let deviceType = detectDeviceType(deviceId)
        if !validateDevice(deviceId, type: deviceType) {
            printDeviceNotFoundError(deviceId)
            return false
        }
        return true
    }

    private func reportOpenResult(_ opened: Bool, for action: TargetAction) {
        switch action {
        case .ios:
            if opened {
                notifier.success("Opened URL on iOS Simulator.")
            } else {
                notifier.error("Failed to open URL on iOS Simulator.")
            }
        case .android(let deviceId):
            let deviceName = AndroidEmulatorHelper.getDeviceFriendlyName(deviceId)
            if opened {
                notifier.success("Opened URL on \(deviceName).")
            } else {
                notifier.error("Failed to open URL on \(deviceName).")
            }
        case .copy:
            if opened {
                notifier.success("Copied URL to clipboard.")
            } else {
                notifier.error("Failed to copy URL to clipboard.")
            }
        case .local:
            if opened {
                notifier.success("Opened URL on this computer.")
            } else {
                notifier.error("Failed to open URL on this computer.")
            }
        case .skip:
            notifier.info("Skipped opening URL.")
        }
    }

    private func targetAction(for deviceId: String) -> TargetAction {
        switch detectDeviceType(deviceId) {
        case .ios:
            return .ios
        case .android, .unknown:
            return .android(deviceId: deviceId)
        }
    }
}

enum DeviceMemory {
    static var lastChoice: String?
    static var shouldUseLast = false
}

func transformUrl(_ urlString: String) -> String {
    let domainsToTransform = [
        "cashstaging.app",
        "cash.app",
        "cash.me"
    ]

    let lowercasedUrl = urlString.lowercased()

    if lowercasedUrl.starts(with: "cashme://") {
        return urlString
    }

    var domainAndPath = urlString
    if lowercasedUrl.starts(with: "https://") {
        domainAndPath = String(urlString.dropFirst("https://".count))
    } else if lowercasedUrl.starts(with: "http://") {
        domainAndPath = String(urlString.dropFirst("http://".count))
    }

    for domain in domainsToTransform where domainAndPath.starts(with: domain.lowercased()) {
        return "cashme://" + domainAndPath
    }

    return urlString
}

@discardableResult
func copyUrlToClipboard(_ text: String) -> Bool {
    let result = Shell.runCommand("/usr/bin/pbcopy", input: text)
    if result.succeeded {
        printSuccess("📋 Copied to clipboard: \(text)")
        return true
    } else {
        printError("Failed to copy to clipboard: \(result.stderr)")
        return false
    }
}

func detectDeviceType(_ deviceId: String) -> DeviceType {
    let uuidPattern = "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"
    if let regex = try? NSRegularExpression(pattern: uuidPattern),
       regex.firstMatch(in: deviceId, range: NSRange(deviceId.startIndex..., in: deviceId)) != nil {
        return .ios
    }

    if deviceId.hasPrefix("emulator-") {
        return .android
    }

    let ipPortPattern = "^\\d+\\.\\d+\\.\\d+\\.\\d+:\\d+$"
    if let regex = try? NSRegularExpression(pattern: ipPortPattern),
       regex.firstMatch(in: deviceId, range: NSRange(deviceId.startIndex..., in: deviceId)) != nil {
        return .android
    }

    return .unknown
}

func validateiOSDevice(_ udid: String) -> Bool {
    let result = Shell.runCommand(
        "/usr/bin/xcrun",
        arguments: ["simctl", "list", "devices", "booted", "-j"],
        suppressStderr: true
    )
    guard result.succeeded,
          let data = result.stdout.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let devices = json["devices"] as? [String: [[String: Any]]] else {
        return false
    }
    for deviceList in devices.values where deviceList.contains(where: {
            ($0["udid"] as? String) == udid && ($0["state"] as? String) == "Booted"
        }) {
        return true
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

    if deviceType == .unknown {
        if validateAndroidDevice(deviceId) {
            deviceType = .android
            alreadyValidated = true
        } else if validateiOSDevice(deviceId) {
            deviceType = .ios
            alreadyValidated = true
        } else {
            printDeviceNotFoundError(deviceId)
            return false
        }
    }

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
        return false
    }
}

func makeAvailableTargetOptions(includesCopyOption: Bool) -> [TargetOption] {
    var availableOptions: [TargetOption] = []

    if SimulatorHelper.getBootedSimulator() != nil {
        availableOptions.append(TargetOption(displayName: "📱 iOS Simulator", action: .ios))
    }

    for device in AndroidEmulatorHelper.getRunningDevices() {
        let friendlyName = AndroidEmulatorHelper.getDeviceFriendlyName(device)
        availableOptions.append(TargetOption(displayName: "📱 \(friendlyName)", action: .android(deviceId: device)))
    }

    if includesCopyOption {
        availableOptions.append(TargetOption(displayName: "📋 Copy to clipboard", action: .copy))
    }
    availableOptions.append(TargetOption(displayName: "💻 Open on this computer", action: .local))
    availableOptions.append(TargetOption(displayName: "⏭️ Skip (don't open)", action: .skip))
    return availableOptions
}

func openUrl(_ urlString: String, action: TargetAction) -> Bool {
    switch action {
    case .ios:
        return SimulatorHelper.openUrl(urlString)
    case .android(let deviceId):
        return AndroidEmulatorHelper.openUrl(urlString, deviceId: deviceId)
    case .copy:
        return copyUrlToClipboard(urlString)
    case .local:
        print("💻 Opening on this computer…")
        let result = Shell.runCommand("/usr/bin/open", arguments: [urlString])
        if result.succeeded {
            printSuccess("Opened URL: \(urlString)")
            return true
        } else {
            printError("Error opening URL: \(result.stderr)")
            return false
        }
    case .skip:
        printInfo("⏭️  Skipped")
        return true
    }
}

func isSupportedUrl(_ string: String) -> Bool {
    let lowercased = string.lowercased()
    return lowercased.starts(with: "http://") ||
        lowercased.starts(with: "https://") ||
        lowercased.starts(with: "cashme://")
}
