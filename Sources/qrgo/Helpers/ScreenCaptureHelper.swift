import Foundation

class ScreenCaptureHelper {
    static func captureSelection() -> String? {
        let tempDir = FileManager.default.temporaryDirectory
        let timestamp = Int(Date().timeIntervalSince1970)
        let imagePath = tempDir.appendingPathComponent("qr_capture_\(timestamp).png").path

        Shell.runCommand("/usr/sbin/screencapture", arguments: ["-i", imagePath])
        return FileManager.default.fileExists(atPath: imagePath) ? imagePath : nil
    }
}
