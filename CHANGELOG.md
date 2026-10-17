# Changelog

User-facing highlights. Detailed build notes are maintained during development; a public release will include its final notes on GitHub Releases.

## Unreleased

The public release is not available yet.

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
