import Foundation

struct ShellResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { exitCode == 0 }

    var trimmedOutput: String {
        stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum Shell {
    @discardableResult
    static func runCommand(
        _ executable: String,
        arguments: [String] = [],
        mergeStderr: Bool = false,
        suppressStderr: Bool = false,
        input: String? = nil
    ) -> ShellResult {
        let task = Process()
        let stdoutPipe = Pipe()

        task.launchPath = executable
        task.arguments = arguments
        task.standardOutput = stdoutPipe

        var stderrPipe: Pipe?
        if mergeStderr {
            task.standardError = stdoutPipe
        } else if suppressStderr {
            task.standardError = FileHandle.nullDevice
        } else {
            let pipe = Pipe()
            task.standardError = pipe
            stderrPipe = pipe
        }

        var inputPipe: Pipe?
        if input != nil {
            let pipe = Pipe()
            task.standardInput = pipe
            inputPipe = pipe
        }

        do {
            try task.run()

            if let inputData = input?.data(using: .utf8) {
                inputPipe?.fileHandleForWriting.write(inputData)
                inputPipe?.fileHandleForWriting.closeFile()
            }

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe?.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()

            return ShellResult(
                exitCode: task.terminationStatus,
                stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                stderr: stderrData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            )
        } catch {
            return ShellResult(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }
    }

    /// Runs a command string via the user's login shell (inherits full PATH).
    static func runLoginShell(_ command: String) -> ShellResult {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/sh"
        return runCommand(shell, arguments: ["-l", "-c", command], suppressStderr: true)
    }
}
