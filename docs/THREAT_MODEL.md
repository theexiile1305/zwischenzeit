# Threat model

Zwischenzeit shows health data of real patients on a phone that is used all day in a practice
and on a watch that patients can see. This document lists what we protect, against whom, how,
and which risks we accept. Report gaps via [SECURITY.md](../SECURITY.md).

## Assets

| Asset | Where it lives |
| --- | --- |
| Patient data (names, appointments, treatments, prescriptions, documentation text) | In memory on the phone; a minimal, privacy-filtered payload on the watch |
| Session tokens (access + refresh JWT) | iOS Keychain |
| Credentials (Einrichtung, Benutzer, Passwort, TOTP) | Typed at sign-in; Einrichtung and Benutzer are remembered in UserDefaults, the password never is |
| Textbausteine | Application Support (file protection: complete); must not contain patient data |

## Trust boundaries

```
 TTools backend ──HTTPS (TLS ≥ 1.2, ATS)── iPhone app ──WatchConnectivity── Apple Watch app ── widget
   (third party)                          (Keychain, memory)                (App Group file)
```

The watch never talks to the backend and holds no credentials.

## Threats and mitigations

| Threat | Mitigation |
| --- | --- |
| Someone picks up the unlocked phone | App lock (Face ID / passcode) on cold start with a stored session and after 5 min in the background; privacy cover in the app switcher. Settings warns when the device has no passcode. |
| Shoulder-surfing via screen recording, AirPlay or mirroring | The privacy cover is shown while the screen is captured. |
| Patients reading the watch | Initials only by default, configurable name/treatment/room; patient text is `privacySensitive` and redacted on a locked watch and on the always-on face when complication data is hidden. |
| Patient data persisted on disk | Ephemeral `URLSession` without `URLCache`, cookies or credential storage (`SecureSession`); no appointment persistence on the phone; drafts in memory only; the watch payload uses complete file protection. |
| Token theft from a backup or another device | Keychain item `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: not in backups, not synced, bound to this device. |
| A stale session after reinstall (the Keychain outlives an uninstall) | The Keychain is cleared on the first launch of a new install. |
| Network attacker | HTTPS only (asserted in `HTTPClient`), ATS defaults, TLS 1.2 minimum. Redirects are followed only to https on the same host (`RedirectGuard`), so the Bearer token never leaves the backend. |
| Keystroke logging by third-party keyboards | Custom keyboards are disabled app-wide. |
| Patient data in logs | OSLog only, with counts and decoding paths; no names, free text or tokens (`print` is banned by SwiftLint). |
| Accidental writes to patient records | Read-only API surface except the documentation text, which is written with an optimistic conflict check. |
| Debug hooks in production | Launch arguments (`-mockAPI`, `-fixedNow`, `-route`, …) are compiled into Debug builds only. |
| Supply chain | No third-party Swift dependencies; CI actions pinned by SHA, tool downloads pinned by SHA-256; Dependabot, CodeQL, Semgrep, mobsfscan, gitleaks, zizmor, OpenSSF Scorecard. |

## Accepted risks

| Risk | Why it is accepted |
| --- | --- |
| No certificate pinning | The backend uses Let's Encrypt with 90-day certificates and rotating intermediates. Pinning would break the app whenever the vendor changes its CA, and we don't control the backend. System trust plus ATS is the baseline. |
| No jailbreak / tamper detection | Trivially bypassed on a compromised device and adds false positives; a compromised OS can read app memory anyway. |
| Tokens readable after first unlock | Background watch sync runs while the phone is locked, so `AfterFirstUnlock` is required. Still device-bound and excluded from backups. |
| The watch complication shows a lock icon, not appointment data, while the watch is locked | The payload file uses complete file protection; privacy wins over glanceability. The widget's reload policy retries soon after, so it resolves quickly once unlocked. |
| Device without a passcode | The app cannot lock without one; it warns in Settings instead of refusing to work. |
| Remembered Einrichtung and Benutzer | Not secret on their own and save typing at every sign-in; the password is never stored. |
| Backend-side security (authorization, rate limits, data retention) | Out of our control; report issues to the TTools vendor. |
