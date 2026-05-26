import Darwin
import Foundation
import XCTest
@testable import qrgo

final class HomebrewUpdateLockProbeTests: XCTestCase {
    func testAbsentUpdateLockReturnsUnlocked() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let state = DarwinHomebrewUpdateLockProbe().updateLockState(homebrewPrefix: directoryURL.path)

        XCTAssertEqual(state, .unlocked)
    }

    func testHeldUpdateLockReturnsHeld() throws {
        let lockURL = try makeUpdateLockFile()
        defer {
            try? FileManager.default.removeItem(at: lockURL.homebrewPrefix)
        }

        let lockHolder = try startLockHolder(updateLock: lockURL.updateLock)
        defer {
            if lockHolder.isRunning {
                lockHolder.terminate()
            }
            lockHolder.waitUntilExit()
        }

        let state = waitForHeldUpdateLock(homebrewPrefix: lockURL.homebrewPrefix)

        guard case .held = state else {
            return XCTFail("Expected held lock state, got \(state).")
        }
    }

    func testUnprobeableUpdateLockReturnsUnavailable() throws {
        let lockURL = try makeUpdateLockFile()
        defer {
            try? FileManager.default.removeItem(at: lockURL.homebrewPrefix)
        }
        try FileManager.default.removeItem(at: lockURL.updateLock)
        try FileManager.default.createDirectory(at: lockURL.updateLock, withIntermediateDirectories: false)

        let state = DarwinHomebrewUpdateLockProbe().updateLockState(homebrewPrefix: lockURL.homebrewPrefix.path)

        guard case .unavailable = state else {
            return XCTFail("Expected unavailable lock state, got \(state).")
        }
    }
}

final class FileQRGoHomebrewRefreshLeaseTests: XCTestCase {
    func testRefreshLeasePreventsConcurrentAcquisition() throws {
        let directoryURL = temporaryLeaseDirectory()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let lease = FileQRGoHomebrewRefreshLease(directoryURL: directoryURL)
        let first = lease.acquire(mode: "refreshIfDue", now: Date())
        let second = lease.acquire(mode: "refreshIfDue", now: Date())

        guard case .acquired(let firstLease) = first else {
            return XCTFail("Expected first lease acquisition to succeed.")
        }
        XCTAssertEqual(second, .unavailable("A QRGo Homebrew metadata refresh is already running."))
        lease.release(firstLease)
    }

    func testRefreshLeaseReleaseAllowsNextAcquisition() throws {
        let directoryURL = temporaryLeaseDirectory()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let lease = FileQRGoHomebrewRefreshLease(directoryURL: directoryURL)
        guard case .acquired(let firstLease) = lease.acquire(mode: "refreshIfDue", now: Date()) else {
            return XCTFail("Expected first lease acquisition to succeed.")
        }

        lease.release(firstLease)

        guard case .acquired = lease.acquire(mode: "refreshIfDue", now: Date()) else {
            return XCTFail("Expected lease acquisition after release to succeed.")
        }
    }

    func testRefreshLeaseReleaseWaitsForMutationLock() throws {
        let directoryURL = temporaryLeaseDirectory()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let lease = FileQRGoHomebrewRefreshLease(directoryURL: directoryURL)
        guard case .acquired(let firstLease) = lease.acquire(mode: "refreshIfDue", now: Date()) else {
            return XCTFail("Expected first lease acquisition to succeed.")
        }
        let mutationLockURL = directoryURL.appendingPathComponent("homebrew-refresh-lease.lock", isDirectory: false)
        let lockHolder = try startLockHolder(updateLock: mutationLockURL, duration: "1")
        defer {
            if lockHolder.isRunning {
                lockHolder.terminate()
            }
            lockHolder.waitUntilExit()
        }
        XCTAssertTrue(waitForHeldLock(mutationLockURL))

        lease.release(firstLease)

        guard case .acquired = lease.acquire(mode: "refreshIfDue", now: Date()) else {
            return XCTFail("Expected release to remove the lease after waiting for the mutation lock.")
        }
    }

    func testRefreshLeaseReplacesStaleLease() throws {
        let directoryURL = temporaryLeaseDirectory()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let lease = FileQRGoHomebrewRefreshLease(directoryURL: directoryURL, staleInterval: -1)
        let first = lease.acquire(mode: "refreshIfDue", now: Date())
        let second = lease.acquire(mode: "refreshIfDue", now: Date())

        guard case .acquired = first else {
            return XCTFail("Expected first lease acquisition to succeed.")
        }
        guard case .acquired = second else {
            return XCTFail("Expected stale lease replacement to succeed.")
        }
    }

    func testRefreshLeaseDoesNotReplaceFreshLeaseCreatedDuringStaleReplacement() throws {
        let directoryURL = temporaryLeaseDirectory()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let now = Date(timeIntervalSince1970: 1_000)
        let leaseURL = try writeLease(
            in: directoryURL,
            id: "stale",
            createdAt: now.addingTimeInterval(-120)
        )
        let lease = FileQRGoHomebrewRefreshLease(
            directoryURL: directoryURL,
            staleInterval: 60,
            beforeReplacingLease: {
                _ = try? writeLease(in: directoryURL, id: "fresh", createdAt: now)
            }
        )

        let result = lease.acquire(mode: "refreshIfDue", now: now)

        XCTAssertEqual(result, .unavailable("A QRGo Homebrew metadata refresh is already running."))
        XCTAssertTrue((try String(contentsOf: leaseURL, encoding: .utf8)).contains(#""id": "fresh""#))
    }

    func testRefreshLeaseSkipsWhenMutationLockIsHeld() throws {
        let directoryURL = temporaryLeaseDirectory()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let mutationLockURL = directoryURL.appendingPathComponent("homebrew-refresh-lease.lock", isDirectory: false)
        _ = FileManager.default.createFile(atPath: mutationLockURL.path, contents: Data())
        let lockHolder = try startLockHolder(updateLock: mutationLockURL)
        defer {
            if lockHolder.isRunning {
                lockHolder.terminate()
            }
            lockHolder.waitUntilExit()
        }
        XCTAssertTrue(waitForHeldLock(mutationLockURL))
        let lease = FileQRGoHomebrewRefreshLease(directoryURL: directoryURL)

        let result = lease.acquire(mode: "refreshIfDue", now: Date())

        XCTAssertEqual(result, .unavailable("A QRGo Homebrew metadata refresh is already running."))
    }

    func testRefreshLeaseTreatsFreshMalformedLeaseAsUnavailable() throws {
        let directoryURL = temporaryLeaseDirectory()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try writeMalformedLease(in: directoryURL)
        let lease = FileQRGoHomebrewRefreshLease(directoryURL: directoryURL, staleInterval: 60)

        let result = lease.acquire(mode: "refreshIfDue", now: Date())

        XCTAssertEqual(result, .unavailable("A QRGo Homebrew metadata refresh is already running."))
    }

    func testRefreshLeaseReplacesStaleMalformedLease() throws {
        let directoryURL = temporaryLeaseDirectory()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let now = Date()
        let leaseURL = try writeMalformedLease(in: directoryURL)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-10)],
            ofItemAtPath: leaseURL.path
        )
        let lease = FileQRGoHomebrewRefreshLease(directoryURL: directoryURL, staleInterval: 1)

        guard case .acquired = lease.acquire(mode: "refreshIfDue", now: now) else {
            return XCTFail("Expected stale malformed lease replacement to succeed.")
        }
    }
}

private func makeUpdateLockFile() throws -> (homebrewPrefix: URL, updateLock: URL) {
    let homebrewPrefix = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let locksDirectory = homebrewPrefix
        .appendingPathComponent("var", isDirectory: true)
        .appendingPathComponent("homebrew", isDirectory: true)
        .appendingPathComponent("locks", isDirectory: true)
    try FileManager.default.createDirectory(at: locksDirectory, withIntermediateDirectories: true)
    let updateLock = locksDirectory.appendingPathComponent("update", isDirectory: false)
    _ = FileManager.default.createFile(atPath: updateLock.path, contents: Data())
    return (homebrewPrefix, updateLock)
}

private func startLockHolder(updateLock: URL, duration: String = "5") throws -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/lockf")
    process.arguments = ["-k", updateLock.path, "/bin/sleep", duration]
    try process.run()
    return process
}

private func waitForHeldUpdateLock(homebrewPrefix: URL) -> HomebrewUpdateLockState {
    let probe = DarwinHomebrewUpdateLockProbe()
    let deadline = Date().addingTimeInterval(2)
    var lastState = probe.updateLockState(homebrewPrefix: homebrewPrefix.path)
    while Date() < deadline {
        if case .held = lastState {
            return lastState
        }
        Thread.sleep(forTimeInterval: 0.05)
        lastState = probe.updateLockState(homebrewPrefix: homebrewPrefix.path)
    }
    return lastState
}

private func waitForHeldLock(_ lockURL: URL) -> Bool {
    let deadline = Date().addingTimeInterval(2)
    while Date() < deadline {
        if lockIsHeld(lockURL) {
            return true
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    return lockIsHeld(lockURL)
}

private func lockIsHeld(_ lockURL: URL) -> Bool {
    let fileDescriptor = open(lockURL.path, O_RDWR)
    guard fileDescriptor >= 0 else {
        return false
    }
    defer {
        close(fileDescriptor)
    }
    if lockf(fileDescriptor, F_TLOCK, 0) == 0 {
        lockf(fileDescriptor, F_ULOCK, 0)
        return false
    }
    return errno == EAGAIN || errno == EACCES
}

private func temporaryLeaseDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
}

@discardableResult
private func writeMalformedLease(in directoryURL: URL) throws -> URL {
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let leaseURL = directoryURL.appendingPathComponent("homebrew-refresh-lease.json", isDirectory: false)
    try "{".write(to: leaseURL, atomically: false, encoding: .utf8)
    return leaseURL
}

@discardableResult
private func writeLease(in directoryURL: URL, id: String, createdAt: Date) throws -> URL {
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let leaseURL = directoryURL.appendingPathComponent("homebrew-refresh-lease.json", isDirectory: false)
    let createdAt = createdAt.timeIntervalSinceReferenceDate
    let json = """
    {
      "id": "\(id)",
      "pid": \(getpid()),
      "processStartedAt": null,
      "createdAt": \(createdAt),
      "mode": "refreshIfDue"
    }
    """
    try json.write(to: leaseURL, atomically: false, encoding: .utf8)
    return leaseURL
}
