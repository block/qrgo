import AppKit
import Foundation

/// Schedules a detached menu bar relaunch, then terminates the current agent so its lock is released.
@MainActor
enum MenuBarRelaunchHelper {
    static func relaunchAfterTermination() -> Bool {
        do {
            let command = try relaunchCommand()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", relaunchScript(command: command)]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            QRGoLogger.menuBarInfo("Scheduled QRGo relaunch.")
            NSApp.terminate(nil)
            return true
        } catch {
            QRGoLogger.menuBarError("Failed to schedule QRGo relaunch: \(error.localizedDescription)")
            return false
        }
    }

    static func relaunchScript(command: String, currentPID: pid_t = getpid()) -> String {
        "while kill -0 \(currentPID) 2>/dev/null; do sleep 0.1; done; \(command)"
    }

    static func relaunchArguments(from currentArguments: [String] = CommandLine.arguments) -> [String] {
        var arguments = [MenuBarLaunchHelper.agentArgument]
        for argument in currentArguments.dropFirst() {
            switch argument {
            case "--transform-urls", "-t", "--copy", "-c":
                arguments.append(argument)
            default:
                continue
            }
        }
        return arguments
    }

    private static func relaunchCommand() throws -> String {
        let arguments = relaunchArguments()
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            return "/usr/bin/open \(shellEscaped(bundleURL.path)) --args \(shellJoined(arguments))"
        }

        return "\(shellEscaped(try ExecutablePathHelper.currentExecutablePath())) \(shellJoined(arguments))"
    }

    private static func shellEscaped(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func shellJoined(_ arguments: [String]) -> String {
        arguments.map(shellEscaped).joined(separator: " ")
    }
}
