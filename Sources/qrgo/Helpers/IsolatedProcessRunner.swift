import Darwin
import Foundation

/// Tracks process groups started by QRGo so cleanup never targets unrelated processes.
final class IsolatedProcessRegistry {
    static let shared = IsolatedProcessRegistry()

    private let lock = NSLock()
    private var processes: [pid_t: String] = [:]

    var hasActiveProcesses: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !processes.isEmpty
    }

    func register(processGroupID: pid_t, description: String) {
        lock.lock()
        processes[processGroupID] = description
        lock.unlock()
    }

    func unregister(processGroupID: pid_t) {
        lock.lock()
        processes.removeValue(forKey: processGroupID)
        lock.unlock()
    }

    func terminateAll(reason: String, escalationDelay: TimeInterval = 2) {
        let processGroups: [pid_t]
        lock.lock()
        processGroups = Array(processes.keys)
        lock.unlock()

        guard !processGroups.isEmpty else {
            return
        }

        QRGoLogger.menuBarWarning("Terminating \(processGroups.count) QRGo-managed process group(s): \(reason)")
        for processGroupID in processGroups {
            terminateProcessGroup(processGroupID, signal: SIGTERM)
        }
        guard escalationDelay > 0 else {
            for processGroupID in processGroups {
                terminateProcessGroup(processGroupID, signal: SIGKILL)
            }
            return
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + escalationDelay) {
            for processGroupID in self.activeProcessGroups(from: processGroups) {
                terminateProcessGroup(processGroupID, signal: SIGKILL)
            }
        }
    }

    private func activeProcessGroups(from processGroups: [pid_t]) -> [pid_t] {
        lock.lock()
        defer { lock.unlock() }
        return processGroups.filter { processes[$0] != nil }
    }
}

protocol IsolatedProcessRunning {
    func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval,
        description: String
    ) async -> ShellResult
}

struct IsolatedProcessRunner: IsolatedProcessRunning {
    private let registry: IsolatedProcessRegistry
    private let terminationDelay: TimeInterval

    init(registry: IsolatedProcessRegistry = .shared, terminationDelay: TimeInterval = 5) {
        self.registry = registry
        self.terminationDelay = terminationDelay
    }

    func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval,
        description: String
    ) async -> ShellResult {
        guard !Task.isCancelled else {
            return ShellResult(exitCode: 143, stdout: "", stderr: "", timedOut: false, cancelled: true)
        }

        let processBox = IsolatedProcessBox(registry: registry, description: description)
        let request = IsolatedProcessRequest(
            executable: executable,
            arguments: arguments,
            environment: environment,
            timeout: timeout,
            description: description
        )

        return await withTaskCancellationHandler {
            await runSpawnedProcess(
                request: request,
                processBox: processBox
            )
        } onCancel: {
            processBox.terminateThenKill(reason: "task cancelled", delay: terminationDelay)
        }
    }

    private func runSpawnedProcess(
        request: IsolatedProcessRequest,
        processBox: IsolatedProcessBox
    ) async -> ShellResult {
        do {
            let process = try spawnProcess(
                executable: request.executable,
                arguments: request.arguments,
                environment: request.environment,
                description: request.description,
                processBox: processBox
            )

            let stdoutTask = Task.detached {
                process.stdoutHandle.readDataToEndOfFile()
            }
            let stderrTask = Task.detached {
                process.stderrHandle.readDataToEndOfFile()
            }
            let waitTask = Task.detached {
                waitForProcess(process.processID)
            }

            let waitResult = await waitForExitOrTimeout(
                waitTask: waitTask,
                timeout: request.timeout,
                processBox: processBox
            )
            if waitResult.cancelled {
                processBox.terminate(reason: "task cancelled")
                await sleepIgnoringCancellation(for: terminationDelay)
                processBox.kill(reason: "task cancelled")
            } else if !waitResult.timedOut {
                processBox.cleanupAfterRootExit()
            }

            process.stdoutHandle.closeFile()
            process.stderrHandle.closeFile()

            let stdout = String(data: await stdoutTask.value, encoding: .utf8) ?? ""
            let stderr = String(data: await stderrTask.value, encoding: .utf8) ?? ""

            processBox.unregister()

            return ShellResult(
                exitCode: waitResult.exitCode,
                stdout: stdout,
                stderr: stderr,
                timedOut: waitResult.timedOut,
                cancelled: waitResult.cancelled || Task.isCancelled
            )
        } catch {
            processBox.unregister()
            return ShellResult(
                exitCode: -1,
                stdout: "",
                stderr: error.localizedDescription,
                timedOut: false,
                cancelled: Task.isCancelled
            )
        }
    }

    private func spawnProcess(
        executable: String,
        arguments: [String],
        environment: [String: String],
        description: String,
        processBox: IsolatedProcessBox
    ) throws -> SpawnedProcess {
        var stdoutPipe = [Int32](repeating: 0, count: 2)
        var stderrPipe = [Int32](repeating: 0, count: 2)
        guard pipe(&stdoutPipe) == 0 else {
            throw POSIXError(.EIO)
        }
        guard pipe(&stderrPipe) == 0 else {
            close(stdoutPipe[0])
            close(stdoutPipe[1])
            throw POSIXError(.EIO)
        }
        do {
            try movePipeDescriptorsAboveStandardIO(&stdoutPipe)
            try movePipeDescriptorsAboveStandardIO(&stderrPipe)
        } catch {
            closePipe(stdoutPipe)
            closePipe(stderrPipe)
            throw error
        }

        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }

        posix_spawn_file_actions_adddup2(&actions, stdoutPipe[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, stderrPipe[1], STDERR_FILENO)
        posix_spawn_file_actions_addclose(&actions, stdoutPipe[0])
        posix_spawn_file_actions_addclose(&actions, stderrPipe[0])
        posix_spawn_file_actions_addclose(&actions, stdoutPipe[1])
        posix_spawn_file_actions_addclose(&actions, stderrPipe[1])

        let flags = Int16(POSIX_SPAWN_SETPGROUP)
        posix_spawnattr_setflags(&attributes, flags)
        posix_spawnattr_setpgroup(&attributes, 0)

        var processID = pid_t()
        let spawnResult = withCStringArray([executable] + arguments) { argv in
            withCStringArray(environment.map { "\($0.key)=\($0.value)" }.sorted()) { envp in
                posix_spawn(&processID, executable, &actions, &attributes, argv, envp)
            }
        }

        close(stdoutPipe[1])
        close(stderrPipe[1])

        guard spawnResult == 0 else {
            close(stdoutPipe[0])
            close(stderrPipe[0])
            throw POSIXError(POSIXErrorCode(rawValue: spawnResult) ?? .EIO)
        }

        let processGroupID = processID
        processBox.register(processGroupID: processGroupID)

        return SpawnedProcess(
            processID: processID,
            stdoutHandle: FileHandle(fileDescriptor: stdoutPipe[0], closeOnDealloc: true),
            stderrHandle: FileHandle(fileDescriptor: stderrPipe[0], closeOnDealloc: true)
        )
    }

    private func waitForExitOrTimeout(
        waitTask: Task<Int32, Never>,
        timeout: TimeInterval,
        processBox: IsolatedProcessBox
    ) async -> ProcessWaitResult {
        let state = ProcessRunState()
        return await withTaskGroup(of: ProcessWaitResult.self) { group in
            group.addTask {
                ProcessWaitResult(
                    exitCode: await waitTask.value,
                    timedOut: state.timedOut,
                    cancelled: state.cancelled || Task.isCancelled
                )
            }
            group.addTask {
                let nanoseconds = UInt64(max(timeout, 0) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else {
                    state.cancelled = true
                    return ProcessWaitResult(exitCode: 143, timedOut: false, cancelled: true)
                }
                state.timedOut = true
                processBox.terminate(reason: "timeout")
                let delayNanoseconds = UInt64(terminationDelay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delayNanoseconds)
                processBox.kill(reason: "timeout")
                return ProcessWaitResult(
                    exitCode: await waitTask.value,
                    timedOut: true,
                    cancelled: false
                )
            }

            let result = await group.next() ?? ProcessWaitResult(exitCode: -1, timedOut: false, cancelled: false)
            if result.timedOut {
                while await group.next() != nil {}
            } else {
                group.cancelAll()
            }
            return result
        }
    }
}

private final class IsolatedProcessBox {
    private let lock = NSLock()
    private let registry: IsolatedProcessRegistry
    private let description: String
    private var processGroupID: pid_t?

    init(registry: IsolatedProcessRegistry, description: String) {
        self.registry = registry
        self.description = description
    }

    func register(processGroupID: pid_t) {
        lock.lock()
        self.processGroupID = processGroupID
        lock.unlock()
        registry.register(processGroupID: processGroupID, description: description)
    }

    func unregister() {
        let registeredProcessGroupID: pid_t?
        lock.lock()
        registeredProcessGroupID = processGroupID
        processGroupID = nil
        lock.unlock()

        if let registeredProcessGroupID = registeredProcessGroupID {
            registry.unregister(processGroupID: registeredProcessGroupID)
        }
    }

    func terminate(reason: String) {
        guard let processGroupID = currentProcessGroupID else {
            return
        }
        QRGoLogger.menuBarWarning("Terminating QRGo-managed process group \(processGroupID): \(reason)")
        terminateProcessGroup(processGroupID, signal: SIGTERM)
    }

    func terminateThenKill(reason: String, delay: TimeInterval) {
        guard let processGroupID = currentProcessGroupID else {
            return
        }
        QRGoLogger.menuBarWarning("Terminating QRGo-managed process group \(processGroupID): \(reason)")
        terminateProcessGroup(processGroupID, signal: SIGTERM)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
            if self?.currentProcessGroupID == processGroupID {
                self?.kill(reason: reason)
            }
        }
    }

    func kill(reason: String) {
        guard let processGroupID = currentProcessGroupID else {
            return
        }
        QRGoLogger.menuBarWarning("Killing QRGo-managed process group \(processGroupID): \(reason)")
        terminateProcessGroup(processGroupID, signal: SIGKILL)
    }

    func cleanupAfterRootExit() {
        guard let processGroupID = currentProcessGroupID else {
            return
        }
        QRGoLogger.menuBarInfo("Cleaning up QRGo-managed process group \(processGroupID) after root process exit.")
        terminateProcessGroup(processGroupID, signal: SIGTERM)
        terminateProcessGroup(processGroupID, signal: SIGKILL)
    }

    private var currentProcessGroupID: pid_t? {
        lock.lock()
        defer { lock.unlock() }
        return processGroupID
    }
}

private struct SpawnedProcess {
    let processID: pid_t
    let stdoutHandle: FileHandle
    let stderrHandle: FileHandle
}

private struct IsolatedProcessRequest {
    let executable: String
    let arguments: [String]
    let environment: [String: String]
    let timeout: TimeInterval
    let description: String
}

private struct ProcessWaitResult {
    let exitCode: Int32
    let timedOut: Bool
    let cancelled: Bool
}

private final class ProcessRunState {
    private let lock = NSLock()
    private var didTimeOut = false
    private var wasCancelled = false

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

    var cancelled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return wasCancelled
        }
        set {
            lock.lock()
            wasCancelled = newValue
            lock.unlock()
        }
    }
}

private func waitForProcess(_ processID: pid_t) -> Int32 {
    var status: Int32 = 0
    while waitpid(processID, &status, 0) == -1 {
        guard errno == EINTR else {
            return -1
        }
    }

    if status & 0x7f == 0 {
        return Int32((status >> 8) & 0xff)
    }
    return Int32(128 + (status & 0x7f))
}

private func terminateProcessGroup(_ processGroupID: pid_t, signal: Int32) {
    guard processGroupID > 0 else {
        return
    }
    kill(-processGroupID, signal)
}

private func movePipeDescriptorsAboveStandardIO(_ pipe: inout [Int32]) throws {
    for index in pipe.indices where pipe[index] <= STDERR_FILENO {
        let movedDescriptor = fcntl(pipe[index], F_DUPFD, STDERR_FILENO + 1)
        guard movedDescriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        close(pipe[index])
        pipe[index] = movedDescriptor
    }
}

private func closePipe(_ pipe: [Int32]) {
    for fileDescriptor in pipe {
        close(fileDescriptor)
    }
}

private func sleepIgnoringCancellation(for delay: TimeInterval) async {
    let nanoseconds = UInt64(max(delay, 0) * 1_000_000_000)
    await Task.detached {
        try? await Task.sleep(nanoseconds: nanoseconds)
    }.value
}

private func withCStringArray<Result>(
    _ strings: [String],
    _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Result
) -> Result {
    let cStrings = strings.map { strdup($0) }
    let pointer = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: cStrings.count + 1)
    for index in cStrings.indices {
        pointer[index] = cStrings[index]
    }
    pointer[cStrings.count] = nil
    defer {
        for cString in cStrings {
            free(cString)
        }
        pointer.deallocate()
    }
    return body(pointer)
}
