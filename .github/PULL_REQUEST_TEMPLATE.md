<!-- Thanks for contributing! Never include patient data, real names, credentials or tokens. -->

## Summary

<!-- What does this change and why? -->

Closes #

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Refactoring (no behavior change)
- [ ] Documentation
- [ ] CI / build / tooling

## Screenshots

<!-- UI changes: light and dark, iPhone (and iPad/Watch if affected). Mock data only (`scripts/screenshot.sh`). -->

| Light | Dark |
| --- | --- |
|  |  |

## How was this tested?

<!-- New or updated tests, manual steps, devices/simulators used. -->

## Checklist

- [ ] `swift test --package-path Packages/ZwischenzeitKit` passes and new logic has tests
- [ ] The iOS and watchOS apps build; watch-unavailable views stay behind `#if !os(watchOS)`
- [ ] Generated files are regenerated and committed (`xcodegen generate`, `gen_swift_tokens.py`)
- [ ] UI uses design tokens; user-facing text is German; new components are in `DesignGalleryView`
- [ ] No patient data, names, free text or tokens in code, fixtures, logs or screenshots
- [ ] No new write call to the TTools backend
- [ ] `UpcomingItem`/`UpcomingPayload` changes stay backward compatible (with a test)
- [ ] `CHANGELOG.md` (and `CLAUDE.md` for architecture/contract changes) updated
