# AGENTS.md

## Build Commands

```bash
swift build              # Debug build
swift build -c release   # Release build (output: .build/release/qrgo)
```

No tests are configured in this project.

## Architecture

- **Sources/qrgo/QRGo.swift** - CLI entry point (`@main` struct) and device/URL handling logic
- **Sources/qrgo/Helpers/**
  - **Shell.swift** - `Shell` enum with `runCommand`/`runLoginShell` static methods, `ShellResult` struct
  - **Colors.swift** - `Colors` enum (ANSI codes) and `printError`/`printSuccess`/`printWarning`/`printInfo` helpers
  - **ScreenCaptureHelper.swift** - Screen region capture via `screencapture`
  - **ScreenCapturePermissionHelper.swift** - Screen recording permission check/request
  - **QRCodeDecoder.swift** - QR/barcode detection from image files via Vision
  - **SimulatorHelper.swift** - iOS Simulator device detection and URL opening
  - **AndroidEmulatorHelper.swift** - Android device/emulator detection and URL opening via ADB
- macOS-only: uses `ScreenCaptureKit`, `Vision`, `CoreImage`, `AppKit` (no external dependencies)
- Requires macOS 12.3+ for `SCShareableContent` screen capture API
- Supports iOS Simulator (`xcrun simctl`) and Android devices (`adb`)

## Code Style

- Swift 5.5+ with async/await; target `.macOS(.v12)` per Package.swift
- `@main` struct pattern with async `main()` entry point
- Shell commands via `Shell.runCommand()` / `Shell.runLoginShell()` static methods
- `Colors` enum for ANSI terminal output; free `printError`/`printSuccess`/`printWarning`/`printInfo` functions
- Error handling: print colored messages via `Colors`, exit with non-zero status codes
- Cache expensive lookups (e.g., `AndroidEmulatorHelper.findAdbPath()`)

## Agent Knowledge Directory

Plans and temporary files can be stored in `.agents/knowledge/` directories.
Review these directories for persistent context about ongoing work.