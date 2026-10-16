# Contributing

Thanks for your interest in NimBar. Contributions should improve the app without weakening macOS security or changing menu bar items without explicit user action.

## Before opening a pull request

- Open an issue first for large changes so the intended behaviour can be discussed.
- Keep changes focused and explain user-visible effects.
- Prefer public Apple APIs. Private macOS interfaces need explicit project approval and a documented fallback and failure mode.
- Do not add telemetry, remote-control interfaces, or runtime dependencies without prior approval.
- Do not change signing, entitlements, permissions, bundle identity, or release settings as part of an unrelated change.
- Never include credentials, certificates, private keys, personal desktop captures, DerivedData, or packaged binaries.
- Preserve third-party copyright and licence notices.

## Development setup

NimBar is a native Xcode project. Development requires a Mac running macOS 27 and Xcode 27. Open NimBar.xcodeproj and select the NimBar scheme. Build and test commands are documented in [TESTING.md](TESTING.md).

Tests must not alter the user's live menu bar. Changes that affect Accessibility, screen capture, input filtering, or menu bar visibility should include a safe automated test for isolated logic and a clearly described manual verification plan.

## Pull requests

Include:

1. The problem and intended behaviour.
2. A summary of implementation choices and any macOS-version assumptions.
3. Tests run, with results stated accurately.
4. Screenshots only when they contain no personal information.

NimBar is licensed under the GNU GPL version 3 as described in [LICENSE](LICENSE). By submitting a contribution, you agree that it may be distributed under that licence.
