# Releasing

Releases follow [Semantic Versioning](https://semver.org). A release is a signed tag `vX.Y.Z`
on a green `main`; the [Release workflow](../.github/workflows/release.yml) publishes the GitHub
Release with the notes from `CHANGELOG.md`, a source archive, `SHA256SUMS.txt` and a signed
build-provenance attestation.

## Steps

1. On a branch, bump the version and the changelog:
   - `project.yml`: `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION` for App Store builds),
     then `xcodegen generate`.
   - `CHANGELOG.md`: move "Unreleased" into `## [X.Y.Z] - YYYY-MM-DD` and update the compare
     links at the bottom.
2. Open a pull request, wait for CI, merge.
3. Tag the merge commit on `main` and push the tag:
   ```sh
   git switch main && git pull --ff-only
   git tag -s vX.Y.Z -m "Zwischenzeit X.Y.Z"
   git push origin vX.Y.Z
   ```
4. Check the release page. The workflow fails if the tag does not match `MARKETING_VERSION` or
   the changelog has no section for the version.

## Verifying a release

```sh
sha256sum -c SHA256SUMS.txt
gh attestation verify zwischenzeit-X.Y.Z-source.tar.gz --repo theexiile1305/zwischenzeit
```

## TestFlight

Uploads run from a maintainer's Mac, not from CI (no signing keys in GitHub).

1. One-time: create the app in App Store Connect with bundle ID `$(BUNDLE_ID_PREFIX).zwischenzeit`,
   fill `Config/Local.xcconfig` (see the example) and sign in to your team in Xcode → Settings → Accounts.
2. `scripts/testflight.sh` archives the app with the embedded watch app, uses a UTC timestamp as
   build number, and uploads it (`Config/ExportOptions.plist`).
3. After processing, add the build to a TestFlight group in App Store Connect.

`ITSAppUsesNonExemptEncryption` is `false` (only the system's HTTPS), so no export-compliance
question appears per build.

## App Store

Not automated. Signing identities never go into this repository or its secrets without a
review of the threat model. A public App Store release needs the TTools vendor's permission
(App Store Review Guideline 5.2.2 requires apps that access a third-party service to be allowed
to do so under its terms).
