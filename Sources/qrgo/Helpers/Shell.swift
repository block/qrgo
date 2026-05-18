import Darwin
import Foundation

struct ShellResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool

    var succeeded: Bool { exitCode == 0 && !timedOut }

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

        var outputReadHandles = [stdoutPipe.fileHandleForReading]
        if let stderrPipe = stderrPipe {
            outputReadHandles.append(stderrPipe.fileHandleForReading)
        }

        do {
            try task.run()

            let timeoutState = TimeoutState()
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

            if let timeout = timeout {
                scheduleTimeout(
                    for: task,
                    after: timeout,
                    outputGroup: outputGroup,
                    outputReadHandles: outputReadHandles,
                    state: timeoutState
                )
            }

            if let inputData = input?.data(using: .utf8) {
                inputPipe?.fileHandleForWriting.write(inputData)
                inputPipe?.fileHandleForWriting.closeFile()
            }

            task.waitUntilExit()
            outputGroup.wait()
            timeoutState.finished = true

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

    private static func scheduleTimeout(
        for task: Process,
        after timeout: TimeInterval,
        outputGroup: DispatchGroup,
        outputReadHandles: [FileHandle],
        state: TimeoutState
    ) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
            guard !state.finished else {
                return
            }

            guard task.isRunning else {
                if outputGroup.wait(timeout: .now()) == .success {
                    return
                }
                state.timedOut = true
                closeOutputReadHandles(outputReadHandles)
                return
            }

            state.timedOut = true
            let terminatedProcessIDs = terminateProcessTree(rootPID: task.processIdentifier, signal: SIGTERM)

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                guard !state.finished else {
                    return
                }
                // A child may keep output pipes open after the root shell exits, so keep the first tree around.
                var processIDs = Set(terminatedProcessIDs)
                if task.isRunning {
                    processIDs.formUnion(processTreeIdentifiers(rootPID: task.processIdentifier))
                } else {
                    processIDs.remove(task.processIdentifier)
                }
                for processID in processIDs {
                    kill(processID, SIGKILL)
                }
                closeOutputReadHandles(outputReadHandles)
            }
        }
    }

    private static func closeOutputReadHandles(_ outputReadHandles: [FileHandle]) {
        for outputReadHandle in outputReadHandles {
            outputReadHandle.closeFile()
        }
    }

    private static func terminateProcessTree(rootPID: pid_t, signal: Int32) -> [pid_t] {
        let processIDs = processTreeIdentifiers(rootPID: rootPID)
        for processID in processIDs {
            kill(processID, signal)
        }
        return processIDs
    }

    private static func processTreeIdentifiers(rootPID: pid_t) -> [pid_t] {
        var processIDs: [pid_t] = []
        for childPID in childProcessIdentifiers(of: rootPID) {
            processIDs.append(contentsOf: processTreeIdentifiers(rootPID: childPID))
        }
        processIDs.append(rootPID)
        return processIDs
    }

    private static func childProcessIdentifiers(of parentPID: pid_t) -> [pid_t] {
        let task = Process()
        let stdoutPipe = Pipe()

        task.launchPath = "/bin/ps"
        task.arguments = ["-axo", "pid=,ppid="]
        task.standardOutput = stdoutPipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            guard task.terminationStatus == 0,
                  let output = String(data: data, encoding: .utf8) else {
                return []
            }

            return output.split(separator: "\n").compactMap { line in
                let columns = line.split(separator: " ")
                guard columns.count == 2,
                      let pid = pid_t(String(columns[0])),
                      let ppid = pid_t(String(columns[1])),
                      ppid == parentPID else {
                    return nil
                }
                return pid
            }
        } catch {
            return []
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
    private var didFinish = false

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

    var finished: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return didFinish
        }
        set {
            lock.lock()
            didFinish = newValue
            lock.unlock()
        }
    }
}
