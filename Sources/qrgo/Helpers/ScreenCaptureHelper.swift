import Foundation

class ScreenCaptureHelper {
    @MainActor
    static func captureSelection(mode: CaptureMode = .drag) throws -> String? {
        let arguments: [String]
        switch mode {
        case .drag:
            arguments = ["-i"]
        case .click:
            guard let rect = SquareCaptureSelector().selectRegion() else { return nil }
            arguments = ["-x", "-R\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))"]
        }
        let tempDir = FileManager.default.temporaryDirectory
        let imagePath = tempDir.appendingPathComponent("qr_capture_\(UUID().uuidString).png").path

        let result = Shell.runCommand("/usr/sbin/screencapture", arguments: arguments + [imagePath])
        if result.exitCode == -1 || (mode == .click && !result.succeeded) {
            try? FileManager.default.removeItem(atPath: imagePath)
            let message = result.stderr.isEmpty ? "Could not capture the selected screen area." : result.stderr
            throw NSError(
                domain: "ScreenCapture", code: Int(result.exitCode), userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        return FileManager.default.fileExists(atPath: imagePath) ? imagePath : nil
    }
}
