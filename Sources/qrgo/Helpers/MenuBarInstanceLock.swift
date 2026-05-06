import Darwin
import Foundation

/// Process-wide lock that keeps QRGo from installing multiple menu bar items.
///
/// Retain the acquired `MenuBarInstanceLock` for the lifetime of the menu bar
/// app. Releasing it unlocks the file and allows another agent to start.
final class MenuBarInstanceLock {
    static func acquire() -> MenuBarInstanceLock? {
        let fileDescriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fileDescriptor >= 0 else {
            QRGoLogger.menuBarError("Failed to open QRGo menu bar lock file.")
            return nil
        }

        guard flock(fileDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(fileDescriptor)
            return nil
        }

        return MenuBarInstanceLock(fileDescriptor: fileDescriptor)
    }

    static var isLockedByAnotherProcess: Bool {
        guard let lock = acquire() else {
            return true
        }
        lock.release()
        return false
    }

    deinit {
        release()
    }

    private let fileDescriptor: Int32
    private var isReleased = false

    private init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
    }

    private func release() {
        guard !isReleased else { return }

        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
        isReleased = true
    }

    private static var lockURL: URL {
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("com.block.qrgo.menubar.lock")
    }
}
