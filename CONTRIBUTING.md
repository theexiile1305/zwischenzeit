# Contributing to Zwischenzeit

Thanks for taking the time to contribute! This document explains how to propose changes.

## Ground rules

1. **No real patient data. Ever.** Not in issues, pull requests, screenshots, test fixtures,
   commit messages or logs. Use `-mockAPI` (or `scripts/screenshot.sh`) for screenshots and
   synthetic data for fixtures.
2. **Read-only by design.** The app must not create, change or delete data in TTools. The only
   write is `TToolsAPI.saveDocumentation`. Pull requests adding other write endpoints will not
   be accepted.
3. **No third-party dependencies** in `Packages/ZwischenzeitKit`.
4. Follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Reporting bugs and requesting features

- Search existing issues first.
- Use the issue templates. Say whether the problem happens with `-mockAPI` too.
- Security vulnerabilities: follow [SECURITY.md](SECURITY.md) instead of opening an issue.

## Development setup

```sh
brew install xcodegen          # only needed if you change project.yml
brew install swiftlint         # optional, CI runs it anyway
cp Config/Local.xcconfig.example Config/Local.xcconfig   # only for device builds
open Zwischenzeit.xcodeproj
```

See the [README](README.md#development) for build, test and screenshot commands and
[CLAUDE.md](CLAUDE.md) for the architecture and backend contract.

### Generated files

| Source | Generated | Command |
| --- | --- | --- |
| `project.yml` | `Zwischenzeit.xcodeproj` | `xcodegen generate` |
| `design/tokens.json` | `Packages/ZwischenzeitKit/Sources/DesignSystem/DesignTokens.swift` | `python3 scripts/gen_swift_tokens.py design/tokens.json Packages/ZwischenzeitKit/Sources/DesignSystem/DesignTokens.swift` |

Never edit the generated files by hand; commit them together with their source. CI fails if
they are out of sync.

## Making a change

1. Fork the repository and create a branch from `main` (`feat/agenda-filter`, `fix/mfa-timeout`).
2. Keep the change focused. Match the surrounding code style.
3. Add or update tests (Swift Testing) for logic changes. Pure logic belongs in the package
   so it can be tested with `swift test`.
4. Run locally before pushing:
   ```sh
   swift test --package-path Packages/ZwischenzeitKit
   swiftlint --strict
   xcodebuild -scheme SettingsFeature -destination 'generic/platform=watchOS Simulator' build
   ```
5. UI changes: attach light and dark screenshots made with mock data.
6. Update `CHANGELOG.md` under "Unreleased" and, if the architecture or backend contract
   changes, `CLAUDE.md`.

### Code guidelines

- Swift 6 strict concurrency; no `@unchecked Sendable` without a comment explaining why.
- Screens and view models depend only on the `TToolsAPI` protocol and domain models.
- All wire-format rules live in `LiveAPI/Mapping.swift`.
- UI uses design tokens (`DS.Color.*`, `DS.Space.*`), never raw values. New components go into
  `DesignGalleryView`.
- User-facing text is German.
- Previews use `PreviewProvider`, not `#Preview` (the package must build with the command line tools).
- Views that are not available on watchOS stay behind `#if !os(watchOS)`.
- `UpcomingItem`/`UpcomingPayload` are exchanged between different app versions: new fields
  must be optional or have a default, with a test decoding an older payload.

### Commit messages

We use [Conventional Commits](https://www.conventionalcommits.org/):
`feat: …`, `fix: …`, `docs: …`, `refactor: …`, `test: …`, `chore: …`, `ci: …`.

## Pull request review

- CI (tests, builds, lint, CodeQL, secret and SAST scans) must be green.
- At least one maintainer approval is required.
- Maintainers may squash commits on merge.

Maintainers: releases are described in [docs/RELEASING.md](docs/RELEASING.md).

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE).
