# Security Policy

Zwischenzeit displays health data of real patients, so we take security reports seriously.

## Supported versions

Only the latest release and the `main` branch receive security fixes.

| Version | Supported |
| --- | --- |
| `main` / latest release | ✅ |
| older releases | ❌ |

## Reporting a vulnerability

**Please do not open public issues, discussions or pull requests for security problems.**

1. Preferred: use GitHub's
   [private vulnerability reporting](https://github.com/theexiile1305/zwischenzeit/security/advisories/new).
2. Alternatively, email **development@michifuchs.com** with the subject `[SECURITY] Zwischenzeit`.

Please include:

- affected version or commit, device and OS version
- a description of the issue and its impact
- steps to reproduce or a proof of concept, using `-mockAPI` data where possible

**Never include real patient data, credentials or session tokens in a report.** If you
accidentally obtained such data, do not share it; tell us what kind of data was exposed instead.

## What to expect

| Step | Target |
| --- | --- |
| Acknowledgement | within 3 business days |
| Initial assessment | within 10 business days |
| Fix or mitigation for confirmed high/critical issues | within 30 days |

We coordinate disclosure with you, credit you in the advisory (unless you prefer otherwise) and
publish a GitHub Security Advisory once a fix is available.

## Threat model

[docs/THREAT_MODEL.md](docs/THREAT_MODEL.md) describes the assets, mitigations and accepted
risks (for example, why there is no certificate pinning). Reports that only restate an accepted
risk are welcome as discussions, not as advisories.

## Scope

In scope: the code in this repository — the iOS/iPadOS app, the watchOS app and widget, the
`ZwischenzeitKit` package, build scripts and CI workflows. Examples: token or credential leakage,
insecure Keychain or file-protection settings, patient data in logs or on disk, the app lock
being bypassable, data reaching the watch against the user's privacy settings, workflow
injection.

Out of scope: the TTools backend (`ttools.app`) itself. This project is not affiliated with its
vendor. Please report backend vulnerabilities directly to the vendor, and do not test against
systems or accounts you are not authorized to use.

## Safe harbor

We will not pursue legal action against researchers who act in good faith, follow this policy,
avoid privacy violations and service disruption, and only use their own accounts and data.
