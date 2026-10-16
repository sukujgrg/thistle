# Maintainers

Thistle follows the ViewTheWord/eucaly release process. Releases run on your
Mac with signing and notarization credentials in Keychain. GitHub Actions
validates the source; the local release command prepares and publishes it.

## Normal release

1. Update `VERSION` to a new numeric `X.Y.Z`, or run
   `scripts/set-version.sh X.Y.Z`.
2. Commit and merge or push the changes to `main`, then update your checkout.
3. Run `make release`.

The command requires a clean checkout, checks the GitHub destination, and waits
for the newest successful **Validate** push run on `main` for that exact commit.
It builds all three executables for Apple Silicon, signs with Developer ID,
notarizes and staples the app, then creates and pushes `v<VERSION>`. It uploads
the saved files to a draft release, verifies them, and publishes it as latest.
There is no manual tagging step.

`VERSION` supplies the marketing version for local and distribution builds;
the checked-in `Info.plist` is a template and is never changed by a build.
Distribution build numbers are automatic UTC timestamps. The app requires
Apple Silicon and macOS 26. The release driver verifies the architecture,
signing team, hardened runtime, and absence of debugging and sandbox
entitlements for `Thistle`, `ThistleEngine`, and `ThistleUpdater`. The engine
must retain its virtualization entitlement.

The destination comes from the single HTTPS GitHub push URL on `origin`, and
must match the app's update repository. Version, tag, build number, repository,
team, signing identity, and validation bypass overrides are not accepted for
release targets. The configured signing team is `E5N29VFW8T` in
`scripts/release.py`; the matching Developer ID Application identity is selected
from Keychain automatically.

## Commands

| Command | Purpose |
| --- | --- |
| `make build` | Build a release configuration app and install it in `~/Applications`. |
| `make run` | Build and open a debug app from `bin/Thistle.app`. |
| `make release` | Validate, build, sign, notarize, tag, and publish. |
| `make release-check` | Check source, destination, and CI without building or publishing. |
| `make release-notarize` | Prepare signed local artifacts without tagging or publishing. |
| `make release-publish` | Publish saved artifacts without building or notarizing again. |
| `make test` | Run offline release regressions and Swift app tests. |
| `make clean` | Remove build caches and `bin/`, preserving `build/release/`. |

The old `release-local` and `release-github` targets have been replaced by
`build` and `release`. For optional notes, use
`make release NOTES_FILE=/tmp/thistle-notes.md`. Notes must be outside the
checkout, including ignored directories. They are saved with the draft and
reused on retries. `NOTARY_PROFILE=ProfileName` selects another local profile.

Local builds keep the existing signing identity selection, with ad-hoc signing
as a fallback. `SIGNING_IDENTITY` can select a certificate for `make build` or
`make run`. `APP_INSTALL_DIR` can change the local installation directory.

## Release Mac setup

Install Xcode 26 / Swift 6.2+, Python 3.9+, and the GitHub CLI. Sign in using
`gh auth login`, and install the Developer ID Application certificate and
private key for team `E5N29VFW8T`. Verify it with:

```sh
security find-identity -v -p codesigning
```

Store notarization credentials once:

```sh
xcrun notarytool store-credentials thistleNotary \
  --apple-id "<apple-id>" \
  --team-id E5N29VFW8T \
  --password "<app-specific-password>"
```

## Saved work and recovery

`build/release/v<VERSION>/` contains `Thistle.app`,
`Thistle-X.Y.Z-notarized.zip`, its `.sha256`, and `.zip.source.txt` metadata.
The existing in-app updater continues to use the zip and checksum assets.
Keep `state.json` and `work/`: they bind the commit, destination, signed app,
Apple submission, and artifact checksums to the release. Distribution builds
use a separate SwiftPM cache in `build/ReleaseSwift/`.

Rerun the same command after an interruption. It reuses the verified signed
app, waits on the saved Apple submission, and uploads only missing draft assets.
`make release-publish` needs no signing identity or Apple credentials once all
artifacts are prepared. A retry after publication verifies the published files
without changing the release or marking it latest again.

Conflicting tags, unrelated drafts, changed artifacts, and a changed latest
release stop publication. Tags are never force-pushed and uploaded files are
never overwritten. Only an empty failed-upload placeholder on the matching
unpublished draft may be removed. Cleanup and release commands share a lock
across linked worktrees; use one publisher across separate clones or Macs.

If Apple received an upload but its submission ID was lost, recover it with:

```sh
xcrun notarytool history --keychain-profile thistleNotary
python3 scripts/release.py --no-publish --resume-notarization SUBMISSION_ID
make release-publish
```

The driver checks Apple's archive SHA-256 before accepting a recovered ID.
Do not edit recovery state to skip steps. If source changes, return to the
recorded commit to finish publishing, or move that preparation directory aside
and prepare the intended source. Use a new `VERSION` when its tag already
belongs to another commit.
