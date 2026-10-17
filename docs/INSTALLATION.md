# Installation

Download NimBar only from the official [GitHub Releases page](https://github.com/emanuele0409/NimBar/releases/tag/v0.2.1-beta.46). No Xcode installation is required for end users.

## DMG

1. Download NimBar.dmg from GitHub Releases.
2. Open the downloaded DMG file.
3. Drag NimBar into the Applications folder.
4. Eject the mounted disk image and open NimBar from Applications.

## ZIP

1. Download NimBar.zip from GitHub Releases.
2. Extract the ZIP archive.
3. Move NimBar.app into Applications.
4. Open NimBar from Applications.

## First launch

The current development build is not notarized by Apple and has no Developer ID distribution signature. macOS may block its first launch. Read [Opening NimBar for the First Time](../SECURITY.md#opening-a-future-download) before responding to a Gatekeeper warning.

Never override a warning that says NimBar is malicious, damaged, or has been modified. Do not disable Gatekeeper or remove the quarantine flag.

## Permissions

NimBar needs Accessibility and Screen Recording to identify supported menu bar items and display their original images. Input Monitoring may be requested only when it is needed for the live drag event filter. Grant the permissions in System Settings and return to NimBar. You can revoke them later in **Privacy & Security**. See [Privacy](../PRIVACY.md#permissions).
