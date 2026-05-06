import Foundation

enum ExecutablePathHelper {
    static func currentExecutablePath() throws -> String {
        let rawPath = CommandLine.arguments[0]
        let fileManager = FileManager.default

        if rawPath.contains("/") {
            let url = URL(fileURLWithPath: rawPath, relativeTo: URL(fileURLWithPath: fileManager.currentDirectoryPath))
                .standardizedFileURL
            if fileManager.isExecutableFile(atPath: url.path) {
                return url.path
            }
        } else {
            let result = Shell.runLoginShell("command -v \(shellEscaped(rawPath))")
            if result.succeeded, !result.trimmedOutput.isEmpty,
               fileManager.isExecutableFile(atPath: result.trimmedOutput) {
                return result.trimmedOutput
            }
        }

        if let bundlePath = Bundle.main.executablePath,
           fileManager.isExecutableFile(atPath: bundlePath) {
            return URL(fileURLWithPath: bundlePath).standardizedFileURL.path
        }

        throw NSError(
            domain: "ExecutablePathHelper",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not resolve the current qrgo executable path."]
        )
    }

    private static func shellEscaped(_ value: String) -> String {
        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
