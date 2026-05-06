import Foundation

/// Persists the most recent supported QR URL so CLI and menu-bar modes can reopen it later.
enum LastScanStore {
    static var lastScannedURL: String? {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static var hasLastScan: Bool {
        guard let lastScannedURL = lastScannedURL else {
            return false
        }
        // The file lives outside the app bundle and can be edited; menu state should reflect reopenability.
        return isSupportedUrl(lastScannedURL)
    }

    @discardableResult
    static func save(_ urlString: String) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try urlString.write(to: fileURL, atomically: true, encoding: .utf8)
            return true
        } catch {
            QRGoLogger.menuBarError("Failed to save last scanned QR URL: \(error.localizedDescription)")
            return false
        }
    }

    private static let directoryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("qrgo", isDirectory: true)

    private static let fileURL = directoryURL.appendingPathComponent("last-scan.txt", isDirectory: false)
}
