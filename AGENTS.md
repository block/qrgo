# AGENTS.md

## Build Commands

```bash
swift build              # Debug build
swift build -c release   # Release build (output: .build/release/qrgo)
```

No tests are configured in this project.

## Architecture

- **Sources/qrgo/main.swift** - Single-file CLI tool for QR code scanning (~800 lines)
- macOS-only: uses ScreenCaptureKit, Vision, CoreImage, AppKit (no external dependencies)
- Requires macOS 12.3+ for `SCShareableContent` screen capture API
- Supports iOS Simulator (`xcrun simctl`) and Android devices (`adb`)

## Code Style

- Swift 5.5+ with async/await; target `.macOS(.v12)` per Package.swift
- `@main` struct pattern with async `main()` entry point
- Helper classes: `ScreenCapturePermissionHelper`, `SimulatorHelper`, `AndroidEmulatorHelper`, `QRCodeDecoder`, `ScreenCaptureHelper`
- `Colors` enum for ANSI terminal output (red, green, yellow, reset)
- Error handling: print colored messages via `Colors`, exit with non-zero status codes
- Use `Process` class for shell commands; cache expensive lookups (e.g., `findAdbPath()`)

## Agent Knowledge Directory

Plans and temporary files can be stored in `.agents/knowledge/` directories.
Review these directories for persistent context about ongoing work.