# Preparing a Release

This is a manual checklist for a future maintainer. It does not publish a release, upload an asset, or create a release workflow. Publish only after the author explicitly decides to do so.

## Version and channel

NimBar currently uses a marketing version and a separate monotonically increasing build number. Keep the app's displayed version, Xcode marketing version, build number, Git tag, release title, and notes consistent.

Use a clear prerelease tag for beta builds, for example `v0.2.1-beta.46`, and mark the GitHub release as a prerelease. Stable tags should use a stable version such as `v0.2.1` and must not be marked prerelease. Increment the build number for each distributed build. Agree on the final tag and version-comparison policy before enabling an updater; see [Update Design](UPDATES.md).

Do not claim support for an architecture or macOS version until a built artifact has been checked on that configuration. The current stated target is macOS 27 and Apple Silicon arm64.

## Before publishing

1. Review the source, changelog, privacy statement, security statement, and known issues.
2. Build and package through the approved local process. Verify the DMG and ZIP contain the intended app and no development files.
3. Verify the app's code signature and architecture. For public direct distribution, establish Developer ID signing and notarization first; the current local development signature is not a substitute.
4. Test installation and first launch on a clean compatible Mac, including Gatekeeper and required permissions.
5. Compute SHA-256 hashes for the final DMG and ZIP after packaging. Record hashes in the release notes for corruption detection; a checksum hosted beside its package does not authenticate the publisher.
6. Create a GitHub release manually, attach only the reviewed DMG and ZIP, mark beta releases as prereleases, and review the draft page and assets before publishing.
7. After publication, update the README's release status and changelog without changing its stable Releases link.

Before enabling issue forms in the new repository, create the project's triage labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, and `wontfix`. The local issue forms use `needs-triage` as their initial label; no labels or GitHub features are created by this document.

No GitHub Actions or unattended release automation is configured by this document.

## Local signing and packaging

Run `sh Scripts/package.sh --check-signing` before packaging, then `sh Scripts/package.sh`.
Both commands need access to the login keychain. When an agent runs inside a sandbox,
`security find-identity` can report zero valid identities even though the imported
certificate and private key are present. Repeat the check with keychain access before
concluding that the `.p12` is missing or importing, revoking, or replacing certificates.

The script pins NimBar's original Apple Development certificate by fingerprint and
checks Team ID `L4R3ATNCT8`. The preflight actually signs and verifies a temporary
executable, proving that the private key is usable. It never falls back to ad hoc
signing or another account's certificate. The original `.p12` does not need to be
available after its identity has been imported into the keychain.

The packaging run verifies the embedded leaf certificate, signs the app and DMG,
verifies the app extracted from the DMG and ZIP, and replaces local outputs only
after all checks pass. Outputs are `build/packages/NimBar.dmg`, `NimBar.zip`, and
`SHA256SUMS.txt`. After replacing the verified outputs, the script removes older
`NimBar-*.dmg` and `NimBar-*.zip` archives and their individual `.sha256` files
from that output folder. Keep one current archive per format; Finder metadata
and unrelated files are preserved. Optional machine-specific overrides use `NIMBAR_SIGNING_IDENTITY`,
`NIMBAR_SIGNING_TEAM`, `NIMBAR_SIGNING_KEYCHAIN`, `NIMBAR_DERIVED_DATA`,
`NIMBAR_PACKAGE_APP`, and `NIMBAR_PACKAGE_OUT`; never store private keys or passwords
in these scripts or in the repository.

Apple Development signing preserves the existing local identity. It does not imply
Developer ID signing or notarization for public distribution.

## Release notes template

Copy and complete this structure for each release:

```markdown
## What's New
- [User-visible highlights]

## Features
- [New features]

## Improvements
- [Usability, compatibility, or performance changes; do not claim unmeasured results]

## Bug Fixes
- [Resolved issues]

## Compatibility
- Minimum macOS version: [verified version]
- Supported architecture: [verified architectures]

## Known Issues
- [Known limitations, or "None known"]

## Installation
- Download the DMG or ZIP from this release.
- See the repository's Installation guide.

## Checksums
- NimBar.dmg — SHA-256: [digest]
- NimBar.zip — SHA-256: [digest]
```

## After publication

- Replace “Public release coming soon” with the version and publication date only after checking the published release.
- Keep the README's Releases link pointing to `https://github.com/emanuele0409/NimBar/releases` rather than a particular asset or a `/latest` endpoint.
- If the release is beta, say so plainly and keep it distinct from stable releases.
- Keep checksums, asset names, architecture labels, and release notes in sync with the uploaded files.
