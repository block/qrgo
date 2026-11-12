import Foundation

/// Keeps AppKit's modal event loop out of the async CLI process.
enum ClickCaptureHelper {
    static let argument = "--capture-square-helper"

    @MainActor
    static func run() -> Never {
        do {
            let selection = SquareCaptureSelector().selectRegion()
            let data = try JSONEncoder().encode(selection)
            FileHandle.standardOutput.write(data)
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Could not return the selected capture region.\n".utf8))
            exit(1)
        }
    }

    static func selectRegion() throws -> CGRect? {
        let executable = try ExecutablePathHelper.currentExecutablePath()
        let result = Shell.runCommand(executable, arguments: [argument])
        if ProcessInfo.processInfo.environment["QRGO_CAPTURE_DEBUG"] == "1" {
            FileHandle.standardError.write(Data(result.stderr.utf8))
        }
        return try selection(from: result)
    }

    static func selection(from result: ShellResult) throws -> CGRect? {
        guard result.succeeded else { throw SelectionError.failed(result.stderr) }
        let decoded: CGRect?
        do {
            decoded = try JSONDecoder().decode(CGRect?.self, from: Data(result.stdout.utf8))
        } catch {
            throw SelectionError.invalidResponse
        }
        guard let selection = decoded else { return nil }
        guard selection.origin.x.isFinite, selection.origin.y.isFinite,
              selection.width.isFinite, selection.height.isFinite,
              selection.size.width > 0, selection.size.height > 0 else {
            throw SelectionError.invalidResponse
        }
        return selection
    }

    enum SelectionError: LocalizedError, Equatable {
        case failed(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .failed(let details):
                return details.isEmpty ? "The click capture helper could not complete selection." : details
            case .invalidResponse:
                return "The click capture helper returned an invalid selection."
            }
        }
    }
}
