import Darwin
import Foundation

struct ShellResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool

    var succeeded: Bool { exitCode == 0 }

    var trimmedOutput: String {
        stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Small synchronous shell wrapper used by CLI and menu bar workflows.
enum Shell {
    @discardableResult
    static func runCommand(
        _ executable: String,
        arguments: [String] = [],
        mergeStderr: Bool = false,
        suppressStderr: Bool = false,
        input: String? = nil,
        timeout: TimeInterval? = nil
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

            let timeoutState = TimeoutState()
            if let timeout = timeout {
                scheduleTimeout(for: task, after: timeout, state: timeoutState)
            }

            if let inputData = input?.data(using: .utf8) {
                inputPipe?.fileHandleForWriting.write(inputData)
                inputPipe?.fileHandleForWriting.closeFile()
            }

            let outputGroup = DispatchGroup()
            let stdoutReader = DataReader()
            let stderrReader = DataReader()

            outputGroup.enter()
            DispatchQueue.global(qos: .utility).async {
                stdoutReader.data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                outputGroup.leave()
            }

            if let stderrPipe = stderrPipe {
                outputGroup.enter()
                DispatchQueue.global(qos: .utility).async {
                    stderrReader.data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    outputGroup.leave()
                }
            }

            task.waitUntilExit()
            outputGroup.wait()

            return ShellResult(
                exitCode: task.terminationStatus,
                stdout: String(data: stdoutReader.data, encoding: .utf8) ?? "",
                stderr: String(data: stderrReader.data, encoding: .utf8) ?? "",
                timedOut: timeoutState.timedOut
            )
        } catch {
            return ShellResult(exitCode: -1, stdout: "", stderr: error.localizedDescription, timedOut: false)
        }
    }

    /// Runs a command string via the user's login shell (inherits full PATH).
    static func runLoginShell(
        _ command: String,
        timeout: TimeInterval? = nil,
        suppressStderr: Bool = true
    ) -> ShellResult {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/sh"
        return runCommand(shell, arguments: ["-l", "-c", command], suppressStderr: suppressStderr, timeout: timeout)
    }

    private static func scheduleTimeout(for task: Process, after timeout: TimeInterval, state: TimeoutState) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
            guard task.isRunning else {
                return
            }

            state.timedOut = true
            task.terminate()

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                guard task.isRunning else {
                    return
                }
                kill(task.processIdentifier, SIGKILL)
            }
        }
    }
}

private final class DataReader {
    private let lock = NSLock()
    private var storedData = Data()

    var data: Data {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedData
        }
        set {
            lock.lock()
            storedData = newValue
            lock.unlock()
        }
    }
}

private final class TimeoutState {
    private let lock = NSLock()
    private var didTimeOut = false

    var timedOut: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return didTimeOut
        }
        set {
            lock.lock()
            didTimeOut = newValue
            lock.unlock()
        }
    }
}
