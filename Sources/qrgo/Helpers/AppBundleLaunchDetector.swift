import Foundation

enum AppBundleLaunchDetector {
    static let bundleIdentifier = "com.block.qrgo"

    static func shouldLaunchMenuBarApp(arguments: [String], bundleIdentifier: String?) -> Bool {
        guard bundleIdentifier == Self.bundleIdentifier else {
            return false
        }

        return arguments.dropFirst().allSatisfy { argument in
            argument.hasPrefix("-psn_")
        }
    }
}
