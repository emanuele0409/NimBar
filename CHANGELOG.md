# Changelog

User-facing highlights. Detailed build notes are maintained during development; public release notes are published on GitHub Releases.

<!-- nimbar-release-sync:changelog:start -->
<!-- release-tag: v1.0.0 -->
## 1.0.0
[Release notes and downloads](https://github.com/emanuele0409/NimBar/releases/tag/v1.0.0)

### What's New

- This is the first stable release and uses the stable update channel. The app presents a concise public version number.

### Improvements

- Refined the settings interface with clearer card outlines, sidebar hover feedback, and accessibility labels.
- Stopped live Layout updates when the settings window closes and resumed them when Layout is reopened.
- Improved the release documentation and added screenshots to help explain General settings, Layout, and hidden icons.

### Performance Optimizations

- Replaced continuous high-frequency modifier polling at idle with modifier-event monitoring and a low-frequency fallback; high-frequency updates are limited to active editing.
- Reduced unnecessary Layout refreshes and writes when cached icon data has not changed.
- Added a targeted Accessibility cache for the menu bar clock, with full rediscovery when references become invalid or the environment changes.
- A development test of the preceding installed version measured 0.14% average idle CPU over five minutes; results depend on the device and conditions. This is not a measurement of every Mac or a guarantee for this release.

### Bug Fixes

- Avoided accepting stale clock-scan results after invalidation or while a clock operation is in progress.
- Improved cleanup of clock observers and input monitors when the app exits.
- Prevented a negative elapsed time from affecting the automatic-hide timer.
- Corrected stable-version presentation and release documentation synchronization when historical build numbers appear in release notes.

### Compatibility and Requirements

- macOS 27 and Apple Silicon are required. NimBar is designed for displays with and without a notch; behavior can vary with macOS and display configuration.
- Accessibility and Screen Recording permissions are needed for supported icon management and previews. Input Monitoring may be requested for the interactive editing gesture.
- When Notification Center is opened from the clock while icons are hidden, those icons may briefly reappear. The interactive divider changes visibility; it does not promise native drag-to-reorder of all icons.
- The update checker opens GitHub for a manual download; automatic installation is not available.

### Installation Notes

- NimBar is free, open source under GPL-3.0, and does not include telemetry.
- Download the DMG or ZIP from this GitHub release. This release uses an Apple Development signature and is not notarized by Apple. See the repository's installation and security instructions for official macOS guidance.
<!-- nimbar-release-sync:changelog:end -->

<!-- release-tag: v0.3.0-beta.62 -->
## 0.3.0 beta — build 62
[Release notes and downloads](https://github.com/emanuele0409/NimBar/releases/tag/v0.3.0-beta.62)

### Highlights

- Restored clicks on the menu bar clock to open and close Notification Center. Hidden icons briefly reappear during activation; no overlay covers the menu bar, so newly appearing icons remain unobstructed.
- Preserved native interaction with visible system controls while handling clicks in empty menu bar areas and hidden icon spaces.
- Made the Layout menu bar strip adapt to the available width, including icons, separators, the clock and the drag placeholder.
- Retained configurable horizontal trackpad and mouse gestures for showing and hiding menu bar icons, with native icon order preserved.

## 0.3.0 beta — build 49

- Added horizontal trackpad and mouse gestures to reveal or re-hide menu bar icons.
- Smoothed the live Command–Option divider and neighbouring icon movement while preserving native icon order.
- Improved display-aware menu bar editing and kept system icons outside the live animation.
- Added a verified local backup of the previous signed installers before replacing release packages.
- Updated the interface and release channel for the 0.3 beta.

## 0.3.0.1 alpha — build 47

- Added an opt-in horizontal swipe to show or hide the Hidden section from empty menu-bar space.
- Added complementary Show/Hide direction pickers in General, saved across launches; defaults are left to show and right to hide.
- Gesture recognition rejects vertical motion, momentum, cross-display strokes, visible menu items, and uncertain hit tests. Always Hidden items and the existing auto-hide policy are preserved.
- Added alpha version display and release-channel filtering; beta and stable clients do not select alpha releases.

## 0.2.1 beta — build 46

- Improved light appearance with a translucent white background, darker descriptions and more distinct cards and sidebar selection. System appearance uses the same contrast when macOS is light.
- Local packaging now retains one verified DMG, one ZIP and a shared checksum file, removing superseded versioned archives only after successful packaging.

## 0.2.1 beta — build 45

- Fixed the native icon selector expanding the original NimBar artwork at its full 210 × 158 point size. The selector now uses a bounded copy of the image, matching the compact height of Chevron.

## 0.2.1 beta — build 44

- Constrained every menu icon option, including the original NimBar mark, to the same 16-point preview frame.
- Set the About version to the specifically requested `0.2.1 beta` for this package.

## 0.2.2 beta — previous local build (build 43)

- Right-clicking a menu-bar area opens NimBar's menu only on verified empty space or the footprint of a managed hidden icon. Visible application and system menu items retain their native right-click behavior; an uncertain accessibility hit test fails closed.

## 0.2.1 beta — build 42

- Added an animated live divider for showing and hiding supported menu bar items while preserving their native order.
- Improved the Layout view's menu bar icon rendering and display-specific scanning.
- Added English and Italian interface languages, light/dark/system appearance, and saved update preferences.
- Added explicit permission guidance for Accessibility and Screen Recording.
- Prepared update settings; GitHub release discovery and installation are not connected.
- Redesigned the settings window with adaptive blur, a unified sidebar, and compact non-scrolling General controls.
- Added a polished About and Credits view with author, license, and repository link; refreshed Layout, Privacy, and Updates panels.
- Improved right-click handling over menu-bar areas left empty by hidden icons.

This development build is not a public release. See [GitHub Releases](https://github.com/emanuele0409/NimBar/releases) for public availability.
