# Release Process

This document outlines the process for creating new releases of qrgo.

## Release Process

The project is configured to automatically update the Homebrew formula and cask when a new version tag is pushed.

1. **Create and Push Version Tag**
   ```bash
   git tag X.Y.Z
   git push origin X.Y.Z
   ```

2. CI will automatically build and publish a release with two artifacts:
   - `qrgo-release.tar.gz` for the CLI formula.
   - `QRGo-X.Y.Z-arm64.zip` for the signed, notarized, stapled `QRGo.app` cask.
3. CI will initialize formula and cask bumps in [block/homebrew-tap](https://github.com/block/homebrew-tap).
4. The tap bumps will open PRs in [block/homebrew-tap](https://github.com/block/homebrew-tap); once approved and merged, you're done.

## Verification

After the release is complete:

1. Test the new version can be installed via Homebrew:
   ```bash
   brew update
   brew upgrade qrgo
   brew install --cask block/tap/qrgo-app
   ```

2. Verify the new version is working:
   ```bash
   qrgo --version
   open /Applications/QRGo.app
   ```
