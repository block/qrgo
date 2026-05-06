# QR Code Scanner

A simple tool that allows you to capture a portion of your screen containing a QR code, decode it, and automatically open the URL in an iOS Simulator or Android emulator.

https://github.com/user-attachments/assets/3fe7a7d3-17a0-4831-a8d7-17e59d591271

## Requirements

- macOS 12.3 or later
- For iOS: XCode and iOS Simulator
- For Android: Android SDK with ADB and at least one configured emulator

## Installation

You can install the QR scanner using Homebrew:

```sh
brew install block/tap/qrgo
```

## Usage

1. Make sure you have either an iOS Simulator or Android emulator running.
2. Run the command:
```sh
qrgo
```
3. Select the area of your screen containing the QR code.
4. The tool will:
   - Save the captured image.
   - Decode any QR codes found.
   - If both iOS and Android emulators are running, prompt you to choose the target platform.
   - Open any valid URLs in the selected emulator.

### Menu Bar Mode

Run QRGo as a persistent macOS menu bar app:

```sh
qrgo --menu-bar
```

This starts QRGo in the menu bar and returns control to your terminal.

Click the menu bar icon to scan a QR code without launching Terminal. When a decoded URL needs a destination, QRGo shows a native macOS chooser with the same options as the terminal flow plus a copy action: iOS Simulator, running Android devices, copy to clipboard, this computer, or skip.

Menu bar logs are written through macOS Unified Logging and can be viewed in Console by filtering for the `com.block.qrgo` subsystem.

Launch the menu bar app automatically at login:

```sh
qrgo --install-login-item
```

Remove the login item:

```sh
qrgo --uninstall-login-item
```

You can also right-click the menu bar icon to scan, toggle launch at login, or quit QRGo.

### Options

```sh
-d, --device <id>      Target a specific device by ID (skips device selection)
                       Android: emulator-5554, 192.168.1.100:5555, or USB serial
                       iOS: Simulator UDID
-t, --transform-urls   Transform specific URLs to use custom URL schemes
                       (e.g., cash.app URLs to cashme:// scheme)
-c, --copy             Copy the parsed URL to clipboard
--menu-bar             Start QRGo as a macOS menu bar app
--install-login-item   Start the menu bar app automatically at login
--uninstall-login-item Stop starting the menu bar app automatically at login
-v, --version          Show installed version
-h, --help             Show help message
```

### Examples

```sh
# Interactive mode - prompts for device selection
qrgo

# Target a specific Android emulator
qrgo -d emulator-5554

# Target a specific iOS Simulator by UDID
qrgo -d A1B2C3D4-E5F6-7890-ABCD-EF1234567890

# Copy URL to clipboard instead of opening
qrgo -c

# Start the menu bar app
qrgo --menu-bar

# Start the menu bar app automatically at login
qrgo --install-login-item

# Combine flags
qrgo -d emulator-5554 -t
```

## Building from Source

If you want to build from source:

```sh
git clone https://github.com/block/qrgo.git
cd qrgo
scripts/build.sh release
```

The build script automatically installs [`xcsift`](https://github.com/ldomaradzki/xcsift) with Homebrew if it is not already available on your `PATH`. The binary will be located at `.build/release/qrgo`.

## Development

Run SwiftLint directly:

```sh
scripts/lint.sh
```

The build script runs SwiftLint before compiling. If SwiftLint is not available on your `PATH`, the lint script automatically installs it with Homebrew.

## Agent Rules

Agent rules are defined in [AGENTS.md](AGENTS.md).

## Contributing

For information about creating new releases, please see [RELEASING.md](RELEASING.md).

## Android Setup

To use the Android emulator support:

1. Make sure you have the Android SDK installed with the `adb` tool available in your PATH
2. Have at least one Android emulator configured and running
3. The tool will automatically detect running Android emulators using `adb devices`
