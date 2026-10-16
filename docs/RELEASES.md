# Preparing a Release

This is a manual checklist for a future maintainer. It does not publish a release, upload an asset, or create a release workflow. Publish only after the author explicitly decides to do so.

## Version and channel

NimBar currently uses a marketing version and a separate monotonically increasing build number. Keep the app's displayed version, Xcode marketing version, build number, Git tag, release title, and notes consistent.

Use a clear prerelease tag for beta builds, for example `v0.2.0-beta.1`, and mark the GitHub release as a prerelease. Stable tags should use a stable version such as `v0.2.0` and must not be marked prerelease. Increment the build number for each distributed build. Agree on the final tag and version-comparison policy before enabling an updater; see [Update Design](UPDATES.md).

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
