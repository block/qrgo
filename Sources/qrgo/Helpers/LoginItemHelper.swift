import Darwin
import Foundation

enum LoginItemHelper {
    static let label = "com.block.qrgo.menubar"

    static var isInstalled: Bool {
        return FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    /// Installs QRGo's user LaunchAgent and optionally bootstraps it immediately.
    ///
    /// If immediate bootstrap fails, the previous plist is restored and
    /// best-effort bootstrapped again so a failed update does not leave launch at
    /// login pointed at a broken replacement.
    @discardableResult
    static func install(loadImmediately: Bool) -> Bool {
        do {
            let executablePath = try ExecutablePathHelper.currentExecutablePath()
            let previousPlistData = try? Data(contentsOf: launchAgentURL)
            try FileManager.default.createDirectory(
                at: launchAgentURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": [
                    executablePath,
                    MenuBarLaunchHelper.agentArgument
                ],
                "RunAtLoad": true,
                "KeepAlive": false,
                "StandardOutPath": "/tmp/\(label).out.log",
                "StandardErrorPath": "/tmp/\(label).err.log"
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: launchAgentURL, options: .atomic)

            if loadImmediately && !loadLaunchAgent() {
                restorePreviousLaunchAgent(from: previousPlistData, reload: true)
                return false
            }

            printSuccess("QRGo menu bar login item installed.")
            return true
        } catch {
            printError("Failed to install QRGo login item: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    static func uninstall() -> Bool {
        unloadLaunchAgent()

        do {
            if FileManager.default.fileExists(atPath: launchAgentURL.path) {
                try FileManager.default.removeItem(at: launchAgentURL)
            }
            printSuccess("QRGo menu bar login item removed.")
            return true
        } catch {
            printError("Failed to remove QRGo login item: \(error.localizedDescription)")
            return false
        }
    }

    private static var launchAgentURL: URL {
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
            .appendingPathComponent("\(label).plist")
    }

    private static func loadLaunchAgent() -> Bool {
        unloadLaunchAgent()

        let result = Shell.runCommand(
            "/bin/launchctl",
            arguments: ["bootstrap", launchDomain, launchAgentURL.path],
            mergeStderr: true
        )
        if result.succeeded {
            return true
        }

        printError("Failed to load QRGo login item: \(result.trimmedOutput)")
        return false
    }

    private static func restorePreviousLaunchAgent(from data: Data?, reload: Bool) {
        do {
            if let data = data {
                try data.write(to: launchAgentURL, options: .atomic)
                if reload && !loadLaunchAgent() {
                    QRGoLogger.menuBarError("Failed to reload the previous QRGo login item.")
                    printError("Failed to reload the previous QRGo login item.")
                }
            } else if FileManager.default.fileExists(atPath: launchAgentURL.path) {
                try FileManager.default.removeItem(at: launchAgentURL)
            }
        } catch {
            printError("Failed to roll back QRGo login item: \(error.localizedDescription)")
        }
    }

    @discardableResult
    private static func unloadLaunchAgent() -> Bool {
        let result = Shell.runCommand(
            "/bin/launchctl",
            arguments: ["bootout", "\(launchDomain)/\(label)"],
            suppressStderr: true
        )
        return result.succeeded
    }

    private static var launchDomain: String {
        return "gui/\(getuid())"
    }

}
