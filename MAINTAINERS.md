# Maintainers

This document is for maintainer-only project operations.

## Notary credentials

Store this project's app-specific password once:

```sh
xcrun notarytool store-credentials thistleNotary \
  --apple-id "<apple-id>" \
  --team-id E5N29VFW8T \
  --password "<app-specific-password>"
```

## Local Release

Notarized local release:

```sh
make release-notarize
```

GitHub release:

```sh
make release-github TAG=vX.Y.Z
```

Verify the Developer ID signing certificate is installed before releasing:

```sh
security find-identity -v -p codesigning
```

The output must include a `Developer ID Application` identity. If multiple identities are available, pass the intended one explicitly:

```sh
make release-github TAG=vX.Y.Z SIGNING_IDENTITY="Developer ID Application: Suku John George (E5N29VFW8T)"
```

Expected release sequence:

```sh
# Update VERSION (and Info.plist CFBundleVersion if the build number changed)
git push
git tag -a vX.Y.Z -m "Thistle X.Y.Z"
git push origin vX.Y.Z
make release-github TAG=vX.Y.Z
```

Release safeguards:

- working tree must be clean
- current branch must not be ahead of upstream
- GitHub release requires a tag already at `HEAD`
- that tag must already exist on `origin`

In-app updates download `Thistle-X.Y.Z-notarized.zip` and its `.sha256` from the GitHub release, then `ThistleUpdater` replaces the running app after quit. Keep both assets on every GitHub release.
