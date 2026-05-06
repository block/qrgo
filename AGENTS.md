# Keep rules and README.md up to date

When project structure, dependencies, plugins, or guidelines are changed: check if `AGENTS.md` or `README.md` need updates, additions, or removals.

# Building from source

Simply execute this to build:

```bash
scripts/build.sh release
```

The generated binary will be located at `.build/release/qrgo`.

# Linting

Run SwiftLint with:

```bash
scripts/lint.sh
```

The lint script auto-installs SwiftLint with Homebrew when missing. `scripts/build.sh` runs this lint step before invoking `swift build`.

Always run `scripts/lint.sh` before creating or amending a commit.

### `xcsift` Output

- Build/test/snapshot wrappers pipe `xcodebuild` through `xcsift -f toon -w` when installed; treat TOON `status` and `summary` as the concise result. `status` is generally `success` or `failed`.
- `summary:` contains indented count fields such as `errors`, `warnings`, `failed_tests`, and `linker_errors`; it can also include `passed_tests`, `build_time`, `test_time`, and `coverage_percent`.
- Inspect TOON sections such as `errors[n]{file,line,message}`, `warnings[n]{file,line,message,type}`, `failed_tests`, `linker_errors`, `slow_tests`, `flaky_tests`, `build_info`, and `executables` when present.
- In `errors[n]{file,line,message}` rows, values are ordered as file path, line number, and quoted message.
- In `warnings[n]{file,line,message,type}` rows, values are ordered as file path, line number, quoted message, and warning type such as `compile` or `swiftui`.
- `linker_errors` entries include `symbol`, `architecture`, `referenced_from`, `message`, and `conflicting_files`; duplicate symbol failures list object paths in `conflicting_files`.
- `failed_tests` entries include `test`, `message`, `file`, `line`, and `duration`; `slow_tests` entries include `test` and `duration`; `flaky_tests` is a list of test names.
- `build_info` can include `targets[n]{name,duration,phases,depends_on}` rows with per-target timing, phases, and dependencies.
- `executables[n]{path,name,target}` lists built artifacts with their path, name, and target.

# Project structure and module organization

## Structure

The project uses Swift Package Manager (SPM) with no external dependencies, relying on native macOS frameworks: `ScreenCaptureKit`, `Vision`, `CoreImage`, and `AppKit`.

- **Sources/qrgo/** - Main source directory
  - **QRGo.swift** - CLI entry point with `@main` struct and command dispatch
  - **QRGoRunner.swift** - Shared QR capture, decode, URL transformation, target selection, and URL opening workflow
  - **MenuBarApp.swift** - AppKit menu bar app, native target chooser, and menu bar notifications/alerts
  - **Helpers/** - Modular helper classes and utilities:
    - `Shell.swift` - Shell command execution (`ShellResult` struct, static methods)
    - `Colors.swift` - ANSI color codes and print helpers (`printError`, `printSuccess`, etc.)
    - `ScreenCaptureHelper.swift` - Screen region capture via `screencapture`
    - `ScreenCapturePermissionHelper.swift` - Screen recording permission checks
    - `QRCodeDecoder.swift` - QR/barcode detection using Vision framework
    - `LastScanStore.swift` - Last scanned QR URL persistence shared by terminal and menu-bar reopen flows
    - `SimulatorHelper.swift` - iOS Simulator detection and URL opening via `xcrun simctl`
    - `AndroidEmulatorHelper.swift` - Android device/emulator detection via ADB
    - `ExecutablePathHelper.swift` - Current executable path resolution for launchers and login items
    - `MenuBarLaunchHelper.swift` - Non-blocking menu bar launcher for the public `--menu-bar` flag
    - `MenuBarInstanceLock.swift` - Single-instance lock for the menu bar agent process
    - `QRGoLogger.swift` - Unified Logging helpers for menu bar logs visible in macOS Console
    - `LoginItemHelper.swift` - LaunchAgent install/remove helpers for starting menu bar mode at login
- **Package.swift** - SPM manifest (requires macOS 12.3+, Swift 5.5+)
- **.swiftlint.yml** - SwiftLint configuration
- **scripts/** - Local development scripts:
  - `lint.sh` - SwiftLint wrapper that auto-installs SwiftLint with Homebrew when missing
  - `build.sh` - Build wrapper that runs SwiftLint, auto-installs `xcsift` with Homebrew when missing, runs `swift build`, and formats output with `xcsift`
- **.build/** - Build artifacts (gitignored)

## Coding style & naming conventions

- **Indentation**: 4 spaces (no tabs)
- **Naming conventions**:
  - Types (classes, structs, enums): `PascalCase` (e.g., `ShellResult`, `AndroidEmulatorHelper`)
  - Functions and variables: `camelCase` (e.g., `getBootedSimulator`, `transformUrl`)
  - Static methods: Prefer static methods on enums/classes for utility functions
- **Swift patterns**:
  - Use `@main` struct with async `main()` entry point
  - Leverage Swift 5.5+ async/await where applicable
  - Use `enum` for namespacing static utilities (e.g., `Colors`, `Shell`)
  - Cache expensive lookups with static private variables (e.g., `_cachedAdbPath`)
- **Error handling**: Print colored error messages via `printError()` and exit with non-zero status codes
- **Shell commands**: Use `Shell.runCommand()` or `Shell.runLoginShell()` static methods; check `ShellResult.succeeded`

## Architecture & design patterns

- **Modular helpers**: Each helper file handles a specific concern (screen capture, QR decoding, device management)
- **Static utility methods**: Helpers use static methods rather than instance methods
- **Result types**: `ShellResult` struct encapsulates command execution results with `exitCode`, `stdout`, `stderr`, and computed `succeeded` property
- **Color-coded output**: All user-facing messages use `printError`, `printSuccess`, `printWarning`, or `printInfo` for consistent terminal output
- **Platform requirements**: macOS 12.3+ required for `SCShareableContent` API
