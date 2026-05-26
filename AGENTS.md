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

The lint script auto-installs SwiftLint and `xcsift` with Homebrew when missing, then pipes SwiftLint's xcode reporter output through `xcsift -f toon -w`. `scripts/build.sh` only invokes `swift build`; run lint separately.

Always run `scripts/lint.sh` before creating or amending a commit.

# Testing

Run XCTest coverage with:

```bash
scripts/test.sh
```

## Menu bar update dry runs

Use dry-run mode when changing or reviewing the menu bar update toast, install modal, retry/error states, or restart copy. Dry-run mode must not invoke Homebrew and is controlled by environment variables:

```bash
QRGO_UPDATE_DRY_RUN=available scripts/run-menu-bar.sh
QRGO_UPDATE_DRY_RUN=current scripts/run-menu-bar.sh
QRGO_UPDATE_DRY_RUN=install-error scripts/run-menu-bar.sh
QRGO_UPDATE_DRY_RUN=check-error scripts/run-menu-bar.sh
```

Use `QRGO_UPDATE_DRY_RUN=available` to validate the update-available toast, Later dismissal, install progress state, success state, and restart action. Use `QRGO_UPDATE_DRY_RUN=current` to validate the no-update path. Use `QRGO_UPDATE_DRY_RUN=install-error` to validate install failure and retry. Use `QRGO_UPDATE_DRY_RUN=check-error` to validate background check failure logging. Adjust artificial delays with `QRGO_UPDATE_CHECK_DELAY_SECONDS` and `QRGO_UPDATE_INSTALL_DELAY_SECONDS`.

Menu bar launch checks are passive. QRGo may perform one delayed, idle, lock-aware Homebrew metadata refresh per day unless `QRGO_DISABLE_BACKGROUND_HOMEBREW_REFRESH=1` or `HOMEBREW_NO_AUTO_UPDATE=1` is set. QRGo uses its own refresh lease and must never delete Homebrew lock files. To inspect the live Homebrew update-lock holder without terminating it:

```bash
HOMEBREW_NO_AUTO_UPDATE=1 lsof "$(HOMEBREW_NO_AUTO_UPDATE=1 brew --prefix)/var/homebrew/locks/update"
```

Homebrew process cleanup is best effort. `SIGKILL`, power loss, OS crashes, and forced user kills can leave Homebrew or QRGo-owned state for the next launch to detect.

### `xcsift` Output

- Build, lint, and test wrappers pipe output through `xcsift -f toon -w`; treat TOON `status` and `summary` as the concise result. `status` is generally `success` or `failed`.
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

The project uses Swift Package Manager (SPM) with no external dependencies, relying on native macOS frameworks: `ScreenCaptureKit`, `Vision`, `CoreImage`, `AppKit`, and `Carbon.HIToolbox`.

- **Sources/qrgo/** - Main source directory
  - **QRGo.swift** - CLI entry point with `@main` struct and command dispatch
  - **QRGoRunner.swift** - Shared QR capture, decode, URL transformation, target selection, and URL opening workflow
  - **MenuBarApp.swift** - AppKit menu bar app, target selection wiring, and menu bar notifications/alerts
  - **MenuBarToastPresenter.swift** - Anchored menu bar notification toast presentation
  - **MenuBarUpdateCoordinator.swift** - Menu bar update check scheduling, visible-session gating, and update prompt coordination
  - **MenuBarUpdateInstallWindow.swift** - AppKit modal window for Homebrew update installation progress, retry, and restart prompt
  - **MenuBarSettingsWindow.swift** - AppKit settings window and keyboard shortcut recorder for menu bar mode
  - **TargetChooserPopoverPresenter.swift** - Anchored AppKit target chooser popover shown from menu bar scans
  - **TargetChooserControls.swift** - Shared AppKit controls used by the target chooser popover
  - **Helpers/** - Modular helper classes and utilities:
    - `AppBundleLaunchDetector.swift` - Detects no-argument launches from the packaged app bundle so `QRGo.app` opens menu bar mode directly
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
    - `MenuBarRelaunchHelper.swift` - Detached relaunch scheduling after menu bar updates
    - `MenuBarInstanceLock.swift` - Single-instance lock for the menu bar agent process
    - `MenuBarModalWindow.swift` - Shared modal window configuration for menu bar AppKit dialogs
    - `QRGoLogger.swift` - Unified Logging helpers for menu bar logs visible in macOS Console
    - `IsolatedProcessRunner.swift` - Direct process runner with QRGo-owned process-group cleanup for Homebrew commands
    - `MenuBarTerminationSignalHandler.swift` - Best-effort SIGTERM cleanup for menu bar-managed background processes
    - `FakeUpdateService.swift` - Dry-run update service for menu bar update UI validation without Homebrew
    - `LoginItemHelper.swift` - LaunchAgent install/remove helpers for starting menu bar mode at login
    - `KeyboardShortcut.swift` - Keyboard shortcut model, display formatting, and macOS shortcut conflict checks
    - `GlobalKeyboardShortcutManager.swift` - Carbon global hotkey registration for menu bar scan actions
    - `MenuBarSettingsStore.swift` - Persisted menu bar settings and shortcut change notifications
    - `HomebrewUpdateService.swift` - Production Homebrew update check/install service for menu bar mode
    - `HomebrewUpdateSupport.swift` - Homebrew executable resolution, refresh state, update-lock probing, and QRGo refresh lease helpers
- **Tests/qrgoTests/** - XCTest coverage for shortcut validation, menu bar settings persistence, menu bar update checks, and target chooser layout
- **Packaging/** - App bundle packaging assets:
  - **QRGo.app/Info.plist** - Template Info.plist used by `scripts/package-app.sh`
  - **QRGo.app/QRGo.icns** - Exported app icon copied into the bundle resources
  - **QRGo.icon/** - Icon Composer source asset for the app icon
- **Package.swift** - SPM manifest (requires macOS 12.3+, Swift 5.5+)
- **.swiftlint.yml** - SwiftLint configuration
- **scripts/** - Local development scripts:
  - `install-xcsift.sh` - Shared wrapper that auto-installs `xcsift` with Homebrew when missing
  - `lint.sh` - SwiftLint wrapper that auto-installs SwiftLint with Homebrew when missing and formats output with `xcsift -f toon -w`
  - `build.sh` - Build wrapper that runs `swift build` and formats output with `xcsift -f toon -w`
  - `package-app.sh` - Builds a local `QRGo.app` bundle around the SPM executable using the packaging assets
  - `test.sh` - XCTest wrapper that runs `swift test` and formats output with `xcsift -f toon -w`
  - `run-menu-bar.sh` - Builds QRGo, stops any running menu bar agent, starts a detached local menu bar app, and returns control to the terminal
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
- **Shell commands**: Use `Shell.runCommand()` or `Shell.runLoginShell()` static methods for ordinary commands; use `IsolatedProcessRunner` when QRGo must own and clean up a process group, such as menu bar Homebrew background work. Check `ShellResult.succeeded`

## Architecture & design patterns

- **Modular helpers**: Each helper file handles a specific concern (screen capture, QR decoding, device management)
- **Static utility methods**: Helpers use static methods rather than instance methods
- **Result types**: `ShellResult` struct encapsulates command execution results with `exitCode`, `stdout`, `stderr`, and computed `succeeded` property
- **Color-coded output**: All user-facing messages use `printError`, `printSuccess`, `printWarning`, or `printInfo` for consistent terminal output
- **Platform requirements**: macOS 12.3+ required for `SCShareableContent` API
