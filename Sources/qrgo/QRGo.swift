import Foundation

@main
struct QRGoMain {
    static func printHelp() {
        print("""
        QRGo - QR Code reader for iOS Simulator and Android Emulator

        Usage: qrgo [options]

        Options:
          -d, --device <id>      Target a specific device by ID (skips device selection)
                                 Android: emulator-5554, 192.168.1.100:5555, or USB serial
                                 iOS: Simulator UDID (e.g., A1B2C3D4-E5F6-7890-ABCD-...)
          -t, --transform-urls   Transform specific URLs to use custom URL schemes
                                 (e.g., cash.app URLs to cashme:// scheme)
          -c, --copy             Copy the parsed URL to clipboard
          --menu-bar             Start QRGo as a macOS menu bar app
          --install-login-item   Start the menu bar app automatically at login
          --uninstall-login-item Stop starting the menu bar app automatically at login
          -v, --version          Show the installed version
          -h, --help             Show this help message
        """)
        exit(0)
    }

    static func printVersion() {
        let command = "brew info --json=v2 block/tap/qrgo | jq -r '.formulae[0].installed[0].version'"
        let result = Shell.runLoginShell(command)
        if result.succeeded, !result.trimmedOutput.isEmpty, result.trimmedOutput != "null" {
            printSuccess("qrgo \(result.trimmedOutput)")
        } else {
            printError("Could not determine installed version. Is qrgo installed via Homebrew?")
            exit(1)
        }
        exit(0)
    }

    @MainActor
    static func main() async {
        let args = CommandLine.arguments

        if args.contains("--help") || args.contains("-h") {
            printHelp()
        }
        if args.contains("--version") || args.contains("-v") {
            printVersion()
        }
        if args.contains("--install-login-item") {
            exit(LoginItemHelper.install(loadImmediately: true) ? 0 : 1)
        }
        if args.contains("--uninstall-login-item") {
            exit(LoginItemHelper.uninstall() ? 0 : 1)
        }

        if args.contains(MenuBarLaunchHelper.agentArgument) {
            MenuBarApp.run(configuration: makeMenuBarConfiguration())
            return
        }
        if args.contains(MenuBarLaunchHelper.launchArgument) {
            exit(MenuBarLaunchHelper.launchDetached(arguments: args) ? 0 : 1)
        }

        let runner = QRGoRunner(
            configuration: makeTerminalConfiguration(),
            targetSelector: TerminalTargetSelector(),
            notifier: TerminalNotifier()
        )
        let succeeded = await runner.run()
        if !succeeded {
            exit(1)
        }
    }

    private static func makeTerminalConfiguration() -> QRGoRunConfiguration {
        return QRGoRunConfiguration(
            shouldTransformUrls: CommandLine.arguments.contains("--transform-urls") ||
                CommandLine.arguments.contains("-t"),
            copyToClipboard: CommandLine.arguments.contains("--copy") ||
                CommandLine.arguments.contains("-c"),
            targetDevice: parseDeviceArgument(),
            showsCapturePath: true,
            showsSelectionPrompt: true,
            showsCopyTargetOption: false
        )
    }

    private static func makeMenuBarConfiguration() -> QRGoRunConfiguration {
        return QRGoRunConfiguration(
            shouldTransformUrls: CommandLine.arguments.contains("--transform-urls") ||
                CommandLine.arguments.contains("-t"),
            copyToClipboard: CommandLine.arguments.contains("--copy") ||
                CommandLine.arguments.contains("-c"),
            targetDevice: nil,
            showsCapturePath: false,
            showsSelectionPrompt: false,
            showsCopyTargetOption: true
        )
    }

    private static func parseDeviceArgument() -> String? {
        let args = CommandLine.arguments
        for (index, arg) in args.enumerated() where arg == "-d" || arg == "--device" {
            guard index + 1 < args.count else {
                printError("-d/--device requires a device ID")
                exit(1)
            }

            let nextArg = args[index + 1]
            if nextArg.hasPrefix("-") {
                printError("-d/--device requires a device ID, not '\(nextArg)'")
                exit(1)
            }
            return nextArg
        }
        return nil
    }
}
