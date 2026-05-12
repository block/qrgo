---
name: release-qrgo
description: Prepare and trigger QRGo releases. Use when the user asks to release QRGo, bump the app version, create a patch/minor/major release, trigger release CI, or publish the formula/cask.
---

# Release QRGo

Versions are tracked using Git tags. The release workflow injects the tag version into the packaged `QRGo.app` bundle.

Before triggering the first release with the app bundle, make sure `#mdx-ios` has configured the `block/apple-codesign-action` secrets documented in `RELEASING.md`.

When asked to bump the version or publish a new release, then…

1. Look at existing Git tags, sorted by semantic versions.
2. Take the newest tag, create an incremented version from it considering major, minor, and patch updates; update x, y, and/or z accordingly. If not sure, ask first. Then execute something like this: `git tag -a [new-version] -m "Release [new-version]"`.
3. Push the new tag: `git push origin [new-version]`. CI will build the CLI tarball, package/sign/notarize/staple `QRGo.app`, and create a GitHub release containing both artifacts.
4. Formula and cask PRs will be opened in [block/homebrew-tap](https://github.com/block/homebrew-tap); once approved and merged, the version is released. Instruct the user to watch that repo for the bump PRs.
