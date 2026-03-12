Versions are tracked solely using Git tags, since the version is not stored in source.

When asked to bump the version or publish a new release, then…

1. Look at existing Git tags, sorted by semantic versions.
2. Take the newest tag, create an incremented version from it considering major, minor, and patch updates; update x, y, and/or z accordingly. If not sure, ask first. Then execute something like this: `git tag -a [new-version] -m "Release [new-version]"`.
3. Push the new tag: `git push origin [new-version]`.
4. You're done, CI will handle the rest.
