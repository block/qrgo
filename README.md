# QR Code Scanner

A simple tool that allows you to capture a portion of your screen containing a QR code, decode it, and automatically open the URL in an iOS Simulator or Android emulator.

https://github.com/user-attachments/assets/910a4490-c1cd-498b-a726-d51c38ae9920

## Requirements

- macOS 12.3 or later
- For iOS: XCode and iOS Simulator
- For Android: Android SDK with ADB and at least one configured emulator

## Installation

Install the menu bar app launcher and ensure the CLI is installed using Homebrew:

```sh
brew install --cask block/tap/qrgo-app
```

This installs `QRGo.app` in Homebrew's cask app directory (`/Applications` by default) and ensures the `qrgo` CLI is installed through the formula dependency.

If you only want the CLI, install the formula directly:

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

Launch `QRGo.app` from `/Applications` to run QRGo as a persistent macOS menu bar app.

You can also start menu bar mode from the CLI:

```sh
qrgo --menu-bar
```

The CLI route starts QRGo in the menu bar and returns control to your terminal.

Click the menu bar icon to scan a QR code without launching Terminal. When a decoded URL needs a destination, QRGo shows a native macOS chooser with the same options as the terminal flow plus a copy action: iOS Simulator, running Android devices, copy to clipboard, this computer, or skip.

The menu bar app also registers a global scan shortcut, `Control-Shift-Q`, chosen to be easier to press while avoiding common macOS shortcuts. Right-click the menu bar icon and open Settings to record a different shortcut or toggle launch at login.

Menu bar logs are written through macOS Unified Logging and can be viewed in Console by filtering for the `com.block.qrgo` subsystem.

Menu bar mode checks the Homebrew cask for updates on launch and once daily while the user session is active, screens are awake, and QRGo is idle. When an update is available, QRGo shows an Install prompt with a temporary Later dismissal and uses Homebrew to upgrade `block/tap/qrgo-app`.

If QRGo was started by launch at login, the installer asks you to quit and reopen QRGo from Applications before installing so Homebrew does not unload the running LaunchAgent mid-upgrade.

Launch the menu bar app automatically at login:

```sh
qrgo --install-login-item
```

Remove the login item:

```sh
qrgo --uninstall-login-item
```

You can also right-click the menu bar icon to scan, reopen the last scanned QR code, open settings, or quit QRGo.

### Options

```sh
-d, --device <id>      Target a specific device by ID (skips device selection)
                       Android: emulator-5554, 192.168.1.100:5555, or USB serial
                       iOS: Simulator UDID
-t, --transform-urls   Transform specific URLs to use custom URL schemes
                       (e.g., cash.app URLs to cashme:// scheme)
-c, --copy             Copy the parsed URL to clipboard
--open-last            Open the last scanned QR code
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

# Open the last scanned QR code and choose a target
qrgo --open-last

# Open the last scanned QR code on a specific device
qrgo --open-last -d emulator-5554

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

The lint script runs SwiftLint's xcode reporter output through [`xcsift -f toon -w`](https://github.com/ldomaradzki/xcsift) so output stays concise for agents. Build and lint are separate invocations. If SwiftLint or xcsift is not available on your `PATH`, the scripts automatically install them with Homebrew.

Run tests:

```sh
scripts/test.sh
```

Run the menu bar app from a local build:

```sh
scripts/run-menu-bar.sh
```

The runner stops any existing QRGo menu bar app, starts the new local build, and then returns control to the terminal.

Pass `release` as the first argument to run the release build instead:

```sh
scripts/run-menu-bar.sh release
```

Dry-run the menu bar update UI without invoking Homebrew:

```sh
QRGO_UPDATE_DRY_RUN=available scripts/run-menu-bar.sh
QRGO_UPDATE_DRY_RUN=current scripts/run-menu-bar.sh
QRGO_UPDATE_DRY_RUN=install-error scripts/run-menu-bar.sh
QRGO_UPDATE_DRY_RUN=check-error scripts/run-menu-bar.sh
```

Use `QRGO_UPDATE_DRY_RUN=current` to validate the no-update path. Use `QRGO_UPDATE_CHECK_DELAY_SECONDS` and `QRGO_UPDATE_INSTALL_DELAY_SECONDS` to adjust artificial delays while validating the toast, Later dismissal, progress, retry, and success states.

Package a local `QRGo.app` bundle:

```sh
scripts/package-app.sh release
open .build/release/QRGo.app
```

## Agent Rules

Agent rules are defined in [AGENTS.md](AGENTS.md).

## Contributing

For information about creating new releases, please see [RELEASING.md](RELEASING.md).

## Android Setup

To use the Android emulator support:

1. Make sure you have the Android SDK installed with the `adb` tool available in your PATH
2. Have at least one Android emulator configured and running
3. The tool will automatically detect running Android emulators using `adb devices`
