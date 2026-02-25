import Foundation

class ScreenCaptureHelper {
    static func captureSelection() throws -> String? {
        let tempDir = FileManager.default.temporaryDirectory
        let timestamp = Int(Date().timeIntervalSince1970)
        let imagePath = tempDir.appendingPathComponent("qr_capture_\(timestamp).png").path

        let result = Shell.runCommand("/usr/sbin/screencapture", arguments: ["-i", imagePath])
        if result.exitCode == -1 {
            throw NSError(domain: "ScreenCapture", code: -1, userInfo: [NSLocalizedDescriptionKey: result.stderr])
        }
        return FileManager.default.fileExists(atPath: imagePath) ? imagePath : nil
    }
}
