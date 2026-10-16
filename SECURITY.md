# Security

## Current distribution status

NimBar is not publicly released yet. The current development build is locally signed, is not signed with a Developer ID distribution identity, and is not notarized by Apple. Do not treat a local build or checksum as proof of publisher identity. A public release should document its signing and notarization status accurately.

## Opening a future download

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
- The current source contains no network updater, telemetry, remote-control listener, or remote command execution path.
- The current build's signature is local and does not establish a trusted Developer ID publisher identity.

## Reporting a vulnerability

Do not post exploit steps, credentials, or sensitive data in a public issue. If GitHub private vulnerability reporting is enabled for this repository, use that channel. Otherwise, contact the maintainer through the [GitHub profile](https://github.com/emanuele0409) to arrange a private report. Security reports should include affected version, macOS version, impact, and safe reproduction details.
