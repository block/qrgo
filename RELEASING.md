# Release Process

This document outlines the process for creating new releases of qrgo.

## Release Process

The project is configured to automatically update the Homebrew formula when a new version tag is pushed

1. **Create and Push Version Tag**
   ```bash
   git tag X.Y.Z
   git push origin X.Y.Z
   ``

2. CI will automatically build and publish bottles to the Block tap

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
