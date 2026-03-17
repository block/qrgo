# QR Code Scanner

A simple CLI tool that allows you to capture a portion of your screen containing a QR code, decode it, and automatically open the URL in an iOS Simulator or Android emulator.

https://github.com/user-attachments/assets/3fe7a7d3-17a0-4831-a8d7-17e59d591271

## Requirements

- macOS 11.0 or later
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

### Options

```sh
-d, --device <id>      Target a specific device by ID (skips device selection)
                       Android: emulator-5554, 192.168.1.100:5555, or USB serial
                       iOS: Simulator UDID
-t, --transform-urls   Transform specific URLs to use custom URL schemes
                       (e.g., cash.app URLs to cashme:// scheme)
-c, --copy             Copy the parsed URL to clipboard
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

# Combine flags
qrgo -d emulator-5554 -t
```

## Building from Source

If you want to build from source:

```sh
git clone https://github.com/block/qrgo.git
cd qrgo
swift build -c release
```

The binary will be located at `.build/release/qrgo`;

## AI Rules

AI rules are defined within the `ai-rules` directory. If they are updated, run `ai-rules generate` to invalidate rules for all agents. 
See [block/ai-rules](https://github.com/block/ai-rules) for installation instructions and other documentation.

## Contributing

For information about creating new releases, please see [RELEASING.md](RELEASING.md).

## Android Setup

To use the Android emulator support:

1. Make sure you have the Android SDK installed with the `adb` tool available in your PATH
2. Have at least one Android emulator configured and running
3. The tool will automatically detect running Android emulators using `adb devices`