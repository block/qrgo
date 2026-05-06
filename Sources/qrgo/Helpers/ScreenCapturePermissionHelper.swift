import Foundation
import ScreenCaptureKit

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
        let result = Shell.runCommand(
            "/usr/bin/open",
            arguments: ["x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"]
        )
        if result.succeeded {
            printInfo("Please enable Screen Recording permission in System Settings and restart the application.")
        } else {
            printError("Error opening System Settings: \(result.stderr)")
        }
    }
}
