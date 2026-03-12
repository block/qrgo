---
description: "Project structure and module organization"
alwaysApply: true
---

## Structure

The project uses Swift Package Manager (SPM) with no external dependencies, relying on native macOS frameworks: `ScreenCaptureKit`, `Vision`, `CoreImage`, and `AppKit`.

- **Sources/qrgo/** - Main source directory
  - **QRGo.swift** - CLI entry point with `@main` struct and device/URL handling logic
  - **Helpers/** - Modular helper classes and utilities:
    - `Shell.swift` - Shell command execution (`ShellResult` struct, static methods)
    - `Colors.swift` - ANSI color codes and print helpers (`printError`, `printSuccess`, etc.)
    - `ScreenCaptureHelper.swift` - Screen region capture via `screencapture`
    - `ScreenCapturePermissionHelper.swift` - Screen recording permission checks
    - `QRCodeDecoder.swift` - QR/barcode detection using Vision framework
    - `SimulatorHelper.swift` - iOS Simulator detection and URL opening via `xcrun simctl`
    - `AndroidEmulatorHelper.swift` - Android device/emulator detection via ADB
- **Package.swift** - SPM manifest (requires macOS 12+, Swift 5.5+)
- **.build/** - Build artifacts (gitignored)

## Coding Style & Naming Conventions

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

## Architecture & Design Patterns

- **Modular helpers**: Each helper file handles a specific concern (screen capture, QR decoding, device management)
- **Static utility methods**: Helpers use static methods rather than instance methods
- **Result types**: `ShellResult` struct encapsulates command execution results with `exitCode`, `stdout`, `stderr`, and computed `succeeded` property
- **Color-coded output**: All user-facing messages use `printError`, `printSuccess`, `printWarning`, or `printInfo` for consistent terminal output
- **Platform requirements**: macOS 12.3+ required for `SCShareableContent` API