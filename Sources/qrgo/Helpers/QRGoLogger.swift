import OSLog

enum QRGoLogger {
    private static let menuBarLogger = Logger(subsystem: "com.block.qrgo", category: "menu-bar")

    static func menuBarError(_ message: String) {
        menuBarLogger.error("\(message, privacy: .public)")
    }

    static func menuBarInfo(_ message: String) {
        menuBarLogger.notice("\(message, privacy: .public)")
    }

    static func menuBarWarning(_ message: String) {
        menuBarLogger.warning("\(message, privacy: .public)")
    }
}
