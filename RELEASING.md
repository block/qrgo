# Release Process

This document outlines the process for creating new releases of qrgo.

## Release Process

The project is configured to automatically update the Homebrew formula when a new version tag is pushed

1. **Create and Push Version Tag**
   ```bash
   git tag X.Y.Z
   git push origin X.Y.Z
   ``

2. The CI will automatically build bottles for all supported platforms
3. Wait for the automated PR to open in [block/homebrew-tap](https://github.com/block/homebrew-tap/pulls) for the new version; approve and merge it.

## Verification

After the release is complete:

1. Test the new version can be installed via Homebrew:
   ```bash
   brew update
   brew upgrade qrgo
   ```

2. Verify the new version is working:
   ```bash
   qrgo --version
   ```
