import Foundation

/// Launches the persistent menu bar process from the public `--menu-bar` command.
///
/// The public command returns control to the terminal after spawning a detached
/// `--menu-bar-agent` process. Only non-interactive scan flags are forwarded
/// because the agent uses AppKit instead of terminal prompts.
enum MenuBarLaunchHelper {
    static let launchArgument = "--menu-bar"
    static let agentArgument = "--menu-bar-agent"

    @discardableResult
    static func launchDetached(arguments: [String]) -> Bool {
        if MenuBarInstanceLock.isLockedByAnotherProcess {
            printInfo("QRGo menu bar app is already running.")
            return true
        }

        do {
            QRGoLogger.menuBarInfo("Launching detached QRGo menu bar process.")

            let process = Process()
            process.executableURL = URL(fileURLWithPath: try ExecutablePathHelper.currentExecutablePath())
            process.arguments = agentArguments(from: arguments)
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            switch waitForAgentToAcquireLock(process) {
            case .launched:
                printSuccess("QRGo menu bar app launched.")
                return true
            case .alreadyRunning:
                printInfo("QRGo menu bar app is already running.")
                return true
            case .failed:
                QRGoLogger.menuBarError("QRGo menu bar app exited before it finished launching.")
                printError("QRGo menu bar app exited before it finished launching.")
                return false
            }
        } catch {
            QRGoLogger.menuBarError("Failed to launch QRGo menu bar app: \(error.localizedDescription)")
            printError("Failed to launch QRGo menu bar app: \(error.localizedDescription)")
            return false
        }
    }

    private static func agentArguments(from arguments: [String]) -> [String] {
        var agentArguments = [agentArgument]
        for argument in arguments.dropFirst() {
            switch argument {
            case "--transform-urls", "-t", "--copy", "-c":
                agentArguments.append(argument)
            default:
                continue
            }
        }
        return agentArguments
    }

    private static func waitForAgentToAcquireLock(_ process: Process) -> AgentLaunchResult {
        for _ in 0..<40 {
            if MenuBarInstanceLock.isLockedByAnotherProcess {
                return process.isRunning ? .launched : .alreadyRunning
            }
            if !process.isRunning {
                return .failed
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        if MenuBarInstanceLock.isLockedByAnotherProcess {
            return process.isRunning ? .launched : .alreadyRunning
        }
        return .failed
    }

    private enum AgentLaunchResult {
        case launched
        case alreadyRunning
        case failed
    }
}
