# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.1] - 2026-10-22

### Fixed

- Apple Watch sync no longer fails silently: queued payloads are no longer dropped when the
  watch isn't paired yet, the watch distinguishes "disabled", "never synced" and "locked" states,
  the widget has a bounded reload fallback instead of `.never`, background-task registration
  uses the version-correct scene modifier, the watch wakes on connectivity updates, and every
  failure point now logs instead of swallowing the error.

### Changed

- Settings copy clarifies that Apple Watch only pairs with iPhone.

## [0.1.0] - 2026-10-20

### Added

- iPhone/iPad calendar for the signed-in therapist: agenda, day, week and month views.
- Appointment details with prescription progress and check-in status.
- Treatment documentation editor with reusable text snippets and conflict detection.
- Apple Watch app, complication and reminder notification with configurable privacy.
- Face ID / passcode app lock and app-switcher privacy cover.
- Mock backend for previews, tests and screenshots.

### Security

- Network layer without HTTP cache, cookies or credential storage; redirects only to https on
  the same host; TLS 1.2 minimum.
- App lock on cold start; privacy cover during screen recording and mirroring; passcode warning.
- Third-party keyboards disabled; Keychain cleared after a reinstall; debug launch arguments
  compiled into Debug builds only; privacy manifests for all targets.

[Unreleased]: https://github.com/theexiile1305/zwischenzeit/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/theexiile1305/zwischenzeit/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/theexiile1305/zwischenzeit/releases/tag/v0.1.0
