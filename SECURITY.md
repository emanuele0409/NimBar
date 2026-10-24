# Security

## Current distribution status

NimBar is publicly available from the official [GitHub Releases page](https://github.com/emanuele0409/NimBar/releases). Current release details and package checksums are published with each release.

Public packages are signed with an Apple Development certificate. They are not notarized and do not use a Developer ID distribution certificate. An Apple Development signature is not the same as a Developer ID distribution signature, and a checksum published beside a package helps detect file changes but does not independently prove who published it. Review the release page and these signing details before opening a download.

## Opening a release download

macOS Gatekeeper may block an app that is not notarized or whose developer cannot be verified. Only consider the following override when all of these are true: you obtained NimBar from the official [NimBar Releases page](https://github.com/emanuele0409/NimBar/releases), you trust that source, and the warning concerns verification/notarization rather than malware or damage.

1. Install NimBar and try to open it normally.
2. If macOS blocks it with a developer-verification warning, close the warning.
3. Open **System Settings → Privacy & Security**.
4. Scroll to **Security** and choose **Open Anyway** for NimBar.
5. Confirm the prompt and open NimBar again.

Apple's macOS 27 guide describes this route. The option generally appears after an attempted launch has been blocked and may only remain available temporarily; its wording can also vary by macOS version and language. See [Apple's macOS 27 guide](https://support.apple.com/en-gb/guide/mac-help/mh40617/27/mac/27) and [Apple's security guidance](https://support.apple.com/it-it/102445).

Do **not** use this override if macOS says the app is malicious, damaged, or has been modified. Do not disable Gatekeeper or System Integrity Protection, remove quarantine attributes, or run commands intended to bypass macOS checks. Stop and obtain a verified copy or contact the maintainer.

## Implementation notes

- NimBar requests visibility changes after explicit user actions in Layout or through the live divider.
- The app uses public Accessibility and ScreenCaptureKit APIs plus undocumented macOS menu bar interfaces for discovery and visibility. Those private interfaces can change without notice.
- The app is not sandboxed. Review [Privacy](PRIVACY.md) for the data it reads and stores.
- The update checker makes read-only HTTPS requests to the public GitHub Releases API only after a manual check or when automatic checks are enabled. It does not execute remote commands or download/install release assets. No telemetry or remote-control listener is present.
- Automatic package installation remains disabled until NimBar can validate package signatures and the app's expected signing identity.
- The public Apple Development signature does not establish the trust provided by a Developer ID distribution identity.

## Reporting a vulnerability

Do not post exploit steps, credentials, or sensitive data in a public issue. If GitHub private vulnerability reporting is enabled for this repository, use that channel. Otherwise, contact the maintainer through the [GitHub profile](https://github.com/emanuele0409) to arrange a private report. Security reports should include affected version, macOS version, impact, and safe reproduction details.
