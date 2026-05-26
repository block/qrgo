import Darwin
import Foundation

protocol HomebrewExecutableResolving {
    func brewExecutablePath() async -> String?
    func homebrewPrefix(brewExecutablePath: String) async -> String?
}

protocol HomebrewUpdateRefreshStoring {
    var lastRefreshAttemptAt: Date? { get set }
    var lastRefreshSucceededAt: Date? { get set }
    var lastRefreshFailureReason: String? { get set }
    var firstRefreshAttemptWithoutSuccessAt: Date? { get set }
}

enum HomebrewUpdateLockState: Equatable {
    case unlocked
    case held(String?)
    case unavailable(String)
}

protocol HomebrewUpdateLockProbing {
    func updateLockState(homebrewPrefix: String) -> HomebrewUpdateLockState
}

struct QRGoHomebrewRefreshLease: Equatable {
    let id: String
}

enum QRGoHomebrewRefreshLeaseResult: Equatable {
    case acquired(QRGoHomebrewRefreshLease)
    case unavailable(String)
}

protocol QRGoHomebrewRefreshLeasing {
    func acquire(mode: String, now: Date) -> QRGoHomebrewRefreshLeaseResult
    func release(_ lease: QRGoHomebrewRefreshLease)
}

struct HomebrewExecutableResolver: HomebrewExecutableResolving {
    private static let candidatePaths = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew"
    ]

    func brewExecutablePath() async -> String? {
        await Storage.shared.brewExecutablePath()
    }

    func homebrewPrefix(brewExecutablePath: String) async -> String? {
        await Storage.shared.homebrewPrefix(brewExecutablePath: brewExecutablePath)
    }

    private final class Storage {
        static let shared = Storage()

        private let lock = NSLock()
        private var cachedBrewPath: String?
        private var cachedPrefix: (brewPath: String, prefix: String)?

        func brewExecutablePath() async -> String? {
            let cachedBrewPath = cachedBrewPathValue()
            if let cachedBrewPath = cachedBrewPath,
               FileManager.default.isExecutableFile(atPath: cachedBrewPath) {
                return cachedBrewPath
            }

            for candidatePath in HomebrewExecutableResolver.candidatePaths where
                FileManager.default.isExecutableFile(atPath: candidatePath) {
                cacheBrewPath(candidatePath)
                return candidatePath
            }

            let result = await Task.detached {
                Shell.runCommand(
                    "/bin/sh",
                    arguments: ["-c", "command -v brew"],
                    suppressStderr: true,
                    timeout: 2
                )
            }.value
            guard result.succeeded,
                  !result.trimmedOutput.isEmpty,
                  FileManager.default.isExecutableFile(atPath: result.trimmedOutput) else {
                return nil
            }
            cacheBrewPath(result.trimmedOutput)
            return result.trimmedOutput
        }

        func homebrewPrefix(brewExecutablePath: String) async -> String? {
            let cachedPrefix = cachedPrefixValue(for: brewExecutablePath)
            if let cachedPrefix = cachedPrefix {
                return cachedPrefix
            }

            let result = await Task.detached {
                Shell.runCommand(
                    "/usr/bin/env",
                    arguments: ["HOMEBREW_NO_AUTO_UPDATE=1", brewExecutablePath, "--prefix"],
                    suppressStderr: true,
                    timeout: 5
                )
            }.value
            guard result.succeeded, !result.trimmedOutput.isEmpty else {
                return nil
            }

            cachePrefix(result.trimmedOutput, brewPath: brewExecutablePath)
            return result.trimmedOutput
        }

        private func cachedBrewPathValue() -> String? {
            lock.lock()
            defer { lock.unlock() }
            return cachedBrewPath
        }

        private func cachedPrefixValue(for brewPath: String) -> String? {
            lock.lock()
            defer { lock.unlock() }
            guard cachedPrefix?.brewPath == brewPath else {
                return nil
            }
            return cachedPrefix?.prefix
        }

        private func cacheBrewPath(_ path: String) {
            lock.lock()
            if cachedBrewPath != path {
                cachedPrefix = nil
            }
            cachedBrewPath = path
            lock.unlock()
        }

        private func cachePrefix(_ prefix: String, brewPath: String) {
            lock.lock()
            cachedPrefix = (brewPath: brewPath, prefix: prefix)
            lock.unlock()
        }
    }
}

struct UserDefaultsHomebrewUpdateRefreshStore: HomebrewUpdateRefreshStoring {
    var userDefaults: UserDefaults = .standard

    var lastRefreshAttemptAt: Date? {
        get { userDefaults.object(forKey: Keys.lastAttempt) as? Date }
        set { userDefaults.set(newValue, forKey: Keys.lastAttempt) }
    }

    var lastRefreshSucceededAt: Date? {
        get { userDefaults.object(forKey: Keys.lastSuccess) as? Date }
        set { userDefaults.set(newValue, forKey: Keys.lastSuccess) }
    }

    var lastRefreshFailureReason: String? {
        get { userDefaults.string(forKey: Keys.lastFailureReason) }
        set { userDefaults.set(newValue, forKey: Keys.lastFailureReason) }
    }

    var firstRefreshAttemptWithoutSuccessAt: Date? {
        get { userDefaults.object(forKey: Keys.firstAttemptWithoutSuccess) as? Date }
        set { userDefaults.set(newValue, forKey: Keys.firstAttemptWithoutSuccess) }
    }

    private enum Keys {
        static let lastAttempt = "menuBar.homebrewMetadataRefresh.lastAttemptAt"
        static let lastSuccess = "menuBar.homebrewMetadataRefresh.lastSucceededAt"
        static let lastFailureReason = "menuBar.homebrewMetadataRefresh.lastFailureReason"
        static let firstAttemptWithoutSuccess = "menuBar.homebrewMetadataRefresh.firstAttemptWithoutSuccessAt"
    }
}

struct DarwinHomebrewUpdateLockProbe: HomebrewUpdateLockProbing {
    func updateLockState(homebrewPrefix: String) -> HomebrewUpdateLockState {
        let locksDirectory = URL(fileURLWithPath: homebrewPrefix)
            .appendingPathComponent("var", isDirectory: true)
            .appendingPathComponent("homebrew", isDirectory: true)
            .appendingPathComponent("locks", isDirectory: true)
        let lockURL = locksDirectory.appendingPathComponent("update", isDirectory: false)
        guard FileManager.default.fileExists(atPath: lockURL.path) else {
            return .unlocked
        }

        let fileDescriptor = open(lockURL.path, O_RDWR)
        guard fileDescriptor >= 0 else {
            if errno == ENOENT {
                return .unlocked
            }
            return .unavailable("Could not open Homebrew update lock for probing.")
        }

        if lockf(fileDescriptor, F_TLOCK, 0) == 0 {
            lockf(fileDescriptor, F_ULOCK, 0)
            close(fileDescriptor)
            return .unlocked
        }

        let lockError = errno
        close(fileDescriptor)

        if lockError == EAGAIN || lockError == EACCES {
            return .held(lockHolderDescription(lockPath: lockURL.path))
        }
        return .unavailable("Could not probe Homebrew update lock.")
    }

    private func lockHolderDescription(lockPath: String) -> String? {
        guard FileManager.default.isExecutableFile(atPath: "/usr/sbin/lsof") else {
            return nil
        }
        let result = Shell.runCommand(
            "/usr/sbin/lsof",
            arguments: [lockPath],
            suppressStderr: true,
            timeout: 2
        )
        guard result.succeeded else {
            return nil
        }
        guard let holderLine = result.stdout
            .split(separator: "\n")
            .dropFirst()
            .first else {
            return nil
        }
        let columns = holderLine.split(separator: " ", maxSplits: 2)
        guard columns.count >= 2 else {
            return nil
        }
        return "\(columns[0]) pid \(columns[1])"
    }
}

struct FileQRGoHomebrewRefreshLease: QRGoHomebrewRefreshLeasing {
    private let fileURL: URL
    private let mutationLockURL: URL
    private let staleInterval: TimeInterval
    private let beforeReplacingLease: (() -> Void)?

    init(
        directoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("qrgo", isDirectory: true),
        staleInterval: TimeInterval = 30 * 60,
        beforeReplacingLease: (() -> Void)? = nil
    ) {
        fileURL = directoryURL.appendingPathComponent("homebrew-refresh-lease.json", isDirectory: false)
        mutationLockURL = directoryURL.appendingPathComponent("homebrew-refresh-lease.lock", isDirectory: false)
        self.staleInterval = staleInterval
        self.beforeReplacingLease = beforeReplacingLease
    }

    func acquire(mode: String, now: Date) -> QRGoHomebrewRefreshLeaseResult {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            return try withLeaseMutationLock(mode: .nonblocking) {
                try acquireLease(mode: mode, now: now)
            } ?? .unavailable("A QRGo Homebrew metadata refresh is already running.")
        } catch {
            return .unavailable("Could not acquire QRGo Homebrew refresh lease.")
        }
    }

    func release(_ lease: QRGoHomebrewRefreshLease) {
        try? withLeaseMutationLock(mode: .blocking) {
            guard let existingLease = readLease(),
                  existingLease.id == lease.id else {
                return
            }
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func acquireLease(mode: String, now: Date) throws -> QRGoHomebrewRefreshLeaseResult {
        let lease = StoredRefreshLease(
            id: UUID().uuidString,
            pid: Int(getpid()),
            processStartedAt: processStartDescription(pid: getpid()),
            createdAt: now,
            mode: mode
        )
        let data = try JSONEncoder().encode(lease)
        let fileDescriptor = open(fileURL.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        if fileDescriptor >= 0 {
            defer {
                close(fileDescriptor)
            }
            do {
                try writeLeaseData(data, to: fileDescriptor)
            } catch {
                try? FileManager.default.removeItem(at: fileURL)
                throw error
            }
            return .acquired(QRGoHomebrewRefreshLease(id: lease.id))
        }

        if errno != EEXIST {
            return .unavailable("Could not acquire QRGo Homebrew refresh lease.")
        }

        guard let existingLease = readLease() else {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return try acquireLease(mode: mode, now: now)
            }
            guard leaseFileIsStale(now: now) else {
                return .unavailable("A QRGo Homebrew metadata refresh is already running.")
            }
            return try replaceExistingLease(mode: mode, now: now, expectedLeaseID: nil)
        }

        if leaseIsStale(existingLease, now: now) {
            return try replaceExistingLease(mode: mode, now: now, expectedLeaseID: existingLease.id)
        }

        return .unavailable("A QRGo Homebrew metadata refresh is already running.")
    }

    private func readLease() -> StoredRefreshLease? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return try? JSONDecoder().decode(StoredRefreshLease.self, from: data)
    }

    private func leaseIsStale(_ lease: StoredRefreshLease, now: Date) -> Bool {
        if now.timeIntervalSince(lease.createdAt) > staleInterval {
            return true
        }
        let pid = pid_t(lease.pid)
        if kill(pid, 0) != 0 && errno == ESRCH {
            return true
        }
        if let storedProcessStart = lease.processStartedAt,
           let currentProcessStart = processStartDescription(pid: pid),
           storedProcessStart != currentProcessStart {
            return true
        }
        return false
    }

    private func leaseFileIsStale(now: Date) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let referenceDate = attributes[.modificationDate] as? Date else {
            return false
        }
        return now.timeIntervalSince(referenceDate) > staleInterval
    }

    private func replaceExistingLease(
        mode: String,
        now: Date,
        expectedLeaseID: String?
    ) throws -> QRGoHomebrewRefreshLeaseResult {
        beforeReplacingLease?()

        if let currentLease = readLease() {
            if let expectedLeaseID, currentLease.id != expectedLeaseID {
                return .unavailable("A QRGo Homebrew metadata refresh is already running.")
            }
            guard leaseIsStale(currentLease, now: now) else {
                return .unavailable("A QRGo Homebrew metadata refresh is already running.")
            }
        } else {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return try acquireLease(mode: mode, now: now)
            }
            guard leaseFileIsStale(now: now) else {
                return .unavailable("A QRGo Homebrew metadata refresh is already running.")
            }
        }

        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            return .unavailable("Could not acquire QRGo Homebrew refresh lease.")
        }
        return try acquireLease(mode: mode, now: now)
    }

    private enum LeaseMutationLockMode {
        case blocking
        case nonblocking
    }

    private func withLeaseMutationLock<Result>(
        mode: LeaseMutationLockMode,
        _ body: () throws -> Result
    ) throws -> Result? {
        let fileDescriptor = open(mutationLockURL.path, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
        guard fileDescriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer {
            close(fileDescriptor)
        }

        let lockCommand = mode == .blocking ? F_LOCK : F_TLOCK
        while lockf(fileDescriptor, lockCommand, 0) != 0 {
            if errno == EINTR {
                continue
            }
            if mode == .nonblocking && (errno == EAGAIN || errno == EACCES) {
                return nil
            }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer {
            lockf(fileDescriptor, F_ULOCK, 0)
        }

        return try body()
    }

    private func processStartDescription(pid: pid_t) -> String? {
        let result = Shell.runCommand(
            "/bin/ps",
            arguments: ["-o", "lstart=", "-p", "\(pid)"],
            suppressStderr: true,
            timeout: 2
        )
        guard result.succeeded else {
            return nil
        }
        let value = result.trimmedOutput
        return value.isEmpty ? nil : value
    }

    private func writeLeaseData(_ data: Data, to fileDescriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return
            }

            var bytesWritten = 0
            while bytesWritten < buffer.count {
                let result = write(
                    fileDescriptor,
                    baseAddress.advanced(by: bytesWritten),
                    buffer.count - bytesWritten
                )
                if result < 0 {
                    if errno == EINTR {
                        continue
                    }
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                guard result > 0 else {
                    throw POSIXError(.EIO)
                }
                bytesWritten += result
            }
        }
    }
}

private struct StoredRefreshLease: Codable {
    let id: String
    let pid: Int
    let processStartedAt: String?
    let createdAt: Date
    let mode: String
}
