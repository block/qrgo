---
name: release-qrgo
description: Prepare and trigger QRGo releases. Use when the user asks to release QRGo, bump the app version, create a patch/minor/major release, trigger release CI, or publish the formula/cask.
---

# Release QRGo

Versions are tracked using Git tags. The release workflow injects the tag version into the packaged `QRGo.app` bundle.

Before triggering the first release with the app bundle, make sure `#mdx-ios` has configured the `block/apple-codesign-action` secrets documented in `RELEASING.md`.

When asked to bump the version or publish a new release, then…

1. Before doing anything release-related, make sure local changes are pushed:
   - Run `git status --short` and stop if there are uncommitted changes unless the user explicitly asks to include or ignore them.
   - Run `git rev-parse --abbrev-ref HEAD` to identify the current branch.
   - Run `git fetch origin`.
   - Verify the current branch has an upstream with `git rev-parse --abbrev-ref --symbolic-full-name @{u}`. If it does not, ask the user where to push.
   - Verify the current branch is not ahead of its upstream with `git rev-list --count @{u}..HEAD`. If it is ahead, push it before continuing.
   - Verify the current branch is not behind its upstream with `git rev-list --count HEAD..@{u}`. If it is behind, stop and ask the user how to reconcile before continuing.
2. Look at existing Git tags, sorted by semantic versions.
3. Take the newest tag, create an incremented version from it considering major, minor, and patch updates; update x, y, and/or z accordingly. If not sure, ask first. Then execute something like this: `git tag -a [new-version] -m "Release [new-version]"`.
4. Push the new tag: `git push origin [new-version]`. CI will build the CLI tarball, package/sign/notarize/staple `QRGo.app`, and create a GitHub release containing both artifacts.
5. Formula and cask PRs will be opened in [block/homebrew-tap](https://github.com/block/homebrew-tap); wait for them to be opened after the dispatch action in qrgo completes, and provide them to the user.
6. Once the tap PRs are approved and merged, the version is released.
