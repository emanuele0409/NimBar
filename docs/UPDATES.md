# NimBar Updates — Technical Plan

This document proposes a future way to connect NimBar updates to GitHub Releases. It is a local planning note: **it does not configure an update source, enable network requests, or install updates**.

## Verified repository state

The following points were checked in the current repository source and packaging script; they describe this checkout, not a published build:

- The Xcode project declares version `0.2.0`, build `38`, macOS deployment target `27.0`, and bundle identifier `com.nimbar.NimBar`.
- The update interface and `AppUpdateController` exist, but the controller is initialized with its default `service: nil`. No GitHub client is present to check releases or download packages; without a service, the interface reports that updates are not configured.
- The local packaging script asks Xcode to use an `Apple Development` signing identity, verifies the signature and Team ID, and does not notarize the package.

These source findings do not independently verify the signature, notarization status, or architecture of any already-built app or archive. Recheck the actual release artifacts before distribution. Apple Development signing is not Developer ID signing.

Source inspected: `NimBar/AppUpdateController.swift`, `NimBar/AppDelegate.swift`, `NimBar.xcodeproj/project.pbxproj`, and `Scripts/package.sh`.

## Release source and update channels

**Proposal:** Once the official repository is public, use only published releases from `emanuele0409/NimBar` over HTTPS. GitHub's REST API permits unauthenticated requests for public resources. The client should not contain personal tokens or credentials with write access. Handle HTTP errors, rate limits, timeouts, malformed responses, and pagination; none should be reported as “NimBar is up to date.” [GitHub REST API: releases](https://docs.github.com/en/rest/releases/releases), [REST API rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api).

GitHub's `GET /repos/{owner}/{repo}/releases/latest` endpoint returns the latest published full release, excluding prereleases and drafts. It therefore cannot discover beta builds. For beta updates, the client would need to list releases, ignore drafts, and select entries marked `prerelease: true`; it must follow GitHub pagination if the list exceeds one page. GitHub documents `created_at` as the date of the commit used for the release, not the date the release was drafted or published, so it should not be treated as `published_at`. [GitHub REST API: releases](https://docs.github.com/en/rest/releases/releases), [managing repository releases](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository).

**Proposed policy:** Keep **stable** and **beta** channels distinct. A stable installation should receive stable releases only. A beta installation may receive beta releases and, if that policy is chosen, stable releases. The channel should be explicit and persistent. GitHub exposes a prerelease flag; it does not define NimBar's channel policy or version comparison rules.

### Version ordering

The current source compares `CFBundleShortVersionString` numerically and compares the build number when versions are equal. Before implementing a real update service, define and test one consistent scheme for release tags, app versions, beta prereleases, and build numbers. The comparator should treat a prerelease as earlier than its corresponding stable release, reject downgrades, and avoid relying on lexicographic tag order, display names, or GitHub dates. Semantic Versioning defines version precedence and prerelease identifiers; NimBar would still need to decide how its internal build number participates. [Semantic Versioning 2.0.0](https://semver.org/).

**Possible convention, not yet adopted:** use tags like `vMAJOR.MINOR.PATCH` for stable and `vMAJOR.MINOR.PATCH-beta.N` for beta, with the macOS build number kept as separate metadata. Do not publish a mixed or ambiguous format until the app comparator has been updated and verified.

## Asset selection and downloads

**Proposal:** Give release assets deterministic names and include only artifacts that have actually been produced and verified. The current project target is Apple Silicon; prepare an arm64 asset. Add an Intel asset only if the project later builds and verifies for Intel. Do not infer an asset's architecture from the release title. A universal asset is appropriate only after verifying the distributed binary's architectures. Before offering an asset, validate the selected release/tag, `draft == false`, prerelease status against the selected channel, supported architecture, exact asset name, reasonable size, and allowed package type.

GitHub release asset metadata includes `browser_download_url`, size, and, when available, a SHA-256 `digest`. The asset download endpoint may return the bytes or redirect (`200` or `302`); a downloader must handle both and restrict connections and redirects to expected HTTPS GitHub Releases hosts. Do not execute scripts or binaries shipped alongside a release. [GitHub REST API: release assets](https://docs.github.com/en/rest/releases/assets).

A checksum can detect accidental corruption when compared with a trusted value. A SHA-256 value fetched from the **same unauthenticated source** as the package does not establish who published it: an attacker able to replace the package may also replace its checksum. A GitHub digest therefore does not replace an independently verified cryptographic update signature or Apple's code signature.

## Authenticity and code signing

For distribution outside the development Mac, Apple's supported route is to sign the app with a **Developer ID Application** certificate, enable Hardened Runtime, and submit the software to Apple's notarization service. Notarization is not App Review: Apple scans the submitted software, returns a ticket that can be stapled where supported, and Gatekeeper uses that ticket during verification. Apple's notarization requirements specify valid Developer ID signing and Hardened Runtime; ad hoc and local development signatures do not satisfy them. [Apple: Developer ID](https://developer.apple.com/developer-id/), [Apple: notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

An ad hoc signature does not identify a developer team, so it is not suitable evidence to users that a public build came from NimBar and should not be the trust basis for automatic updates. A local development signature must not be described as Developer ID signing or notarization. Before distribution, verify that the installed app and update preserve the intended code-signing identity. Apple's code-signing requirements and designated requirements participate in how code identity is recognized. [Apple TN3127: code-signing requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

### Evaluate Sparkle 2

**Proposal:** Evaluate Sparkle 2 as the first candidate for native macOS updates before maintaining a custom installer. Sparkle uses an appcast to describe releases and assets and supports update channels through the feed. Its configuration includes `SUFeedURL` and a public EdDSA key (`SUPublicEDKey`). Update archives must carry an EdDSA signature generated with a securely held private key and verified against the public key embedded in the app. [Sparkle documentation](https://sparkle-project.org/documentation/), [customization and feed settings](https://sparkle-project.org/documentation/customization/), [publishing an update](https://sparkle-project.org/documentation/publishing/).

Sparkle's EdDSA key is separate from Apple's Developer ID certificate; the two checks serve different purposes and do not replace each other. Never put the EdDSA private key in the app, repository, public CI, or feed. Consider a signed feed (`SURequireSignedFeed`) only after planning key storage and rotation; Sparkle documents signed-feed validation as available starting with Sparkle 2.9. Keep Sparkle current and review its security notes before adoption. [Sparkle security and reliability](https://sparkle-project.org/documentation/security-and-reliability/).

Before choosing Sparkle, assess whether it and its XPC installer service fit NimBar's current configuration without requiring an unapproved change to sandboxing, permissions, or architecture. If they do not fit, design a bundle replacement path with equivalent validation of the Developer ID signature, bundle ID, Team ID/designated requirement, archive, and Gatekeeper status. Do not implement a simple unzip-and-replace mechanism.

## Proposed safe update flow

1. Make a read-only HTTPS request to the official releases source. Do not send preferences, user identifiers, app inventory, permissions, or menu-bar data. Network access should be limited to explicit update checks and the automatic mode selected by the user.
2. Select the appropriate channel and compare version/build using the defined comparator. Do not install incomplete, incompatible, unsigned, or draft release data.
3. Show the version, channel, release notes, and size before downloading. Automatic modes must follow the user's preference and must not restart NimBar during a drag or active use of its UI.
4. Download to a private temporary directory with size limits, timeouts, and cleanup for incomplete files. Check the digest for corruption and, above all, validate the archive's EdDSA signature (with Sparkle) and the extracted app's Developer ID signature/notarization.
5. Check bundle ID `com.nimbar.NimBar`, version/build, architecture, signature, and expected identity. Reject downgrades, unsigned binaries, unexpected Team ID/designated requirements, modified bundles, and insufficient write permissions. Do not ask users to disable Gatekeeper or SIP and do not remove quarantine with `xattr`.
6. Replace only the installed, validated NimBar app through a mechanism that safely handles permissions, shutdown, and relaunch. Keep the previous app until replacement has been verified, then relaunch NimBar and confirm the installed version. If any step fails, cancel and preserve the existing version.

Manual installation instructions should explain Gatekeeper in a way that matches the release's actual signing and notarization status. Do not recommend global security exceptions or removing quarantine.

## Roadmap before enabling network access

- [ ] Create and publish the repository and Releases pages only when explicitly requested by the author.
- [ ] Choose the tag/version/build scheme and stable/beta policy; add comparator and downgrade test cases.
- [ ] Define arm64 asset names. Test an Intel binary in the future before claiming Intel support.
- [ ] Obtain and validate Developer ID Application signing, Hardened Runtime, Apple notarization, and stapling for the app/DMG; test Gatekeeper on a clean Mac.
- [ ] Evaluate a current Sparkle 2 release, including compatibility with NimBar's configuration, XPC service, channels, and key management.
- [ ] Define an official HTTPS appcast and separate stable and beta feeds; keep the EdDSA private key outside the repository and hosting server.
- [ ] Implement read-only public requests, asset/architecture selection, signature validation, temporary download, installation, and rollback. Do not embed GitHub credentials in the client.
- [ ] Verify manual checks, automatic checks only, and automatic download/install, including offline network, rate limiting, malformed feeds, invalid signatures, interrupted downloads, insufficient disk space, and canceled installs.
- [ ] Only after these steps connect the service to `AppUpdateController` and remove the “Updates not configured” state.

## Official sources

- [GitHub REST API — releases](https://docs.github.com/en/rest/releases/releases)
- [GitHub REST API — release assets](https://docs.github.com/en/rest/releases/assets)
- [GitHub — managing repository releases](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)
- [GitHub REST API — rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api)
- [Apple Developer ID](https://developer.apple.com/developer-id/)
- [Apple — notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Apple TN3127 — code-signing requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)
- [Sparkle 2 documentation](https://sparkle-project.org/documentation/)
- [Sparkle — publishing updates](https://sparkle-project.org/documentation/publishing/)
- [Sparkle — customization and feed settings](https://sparkle-project.org/documentation/customization/)
- [Sparkle — security and reliability](https://sparkle-project.org/documentation/security-and-reliability/)
- [Semantic Versioning 2.0.0](https://semver.org/)
