# Privacy

This document describes the current NimBar source.

## Data NimBar uses

NimBar reads the labels, identifiers, owning app bundle identifiers, process IDs, and screen coordinates that macOS exposes for menu bar items. It captures the menu bar area to show original item images in Layout. This processing happens locally after the relevant macOS permissions are granted.

The current implementation stores preferences locally, including layout assignments, display and appearance choices, language, shortcut modifiers, and update mode. It also keeps a local cache of menu bar icon image data in the app's preferences so previously hidden icons can remain recognisable in Layout. These values are not uploaded by the current build.

## Network and telemetry

NimBar has no telemetry, analytics, or remote-control service. When you manually check for updates, or enable automatic checks, NimBar makes a read-only HTTPS request to the public GitHub Releases API for `emanuele0409/NimBar`. GitHub receives ordinary connection metadata such as the request time and your network address. NimBar sends no account token, menu bar data, app inventory, permission state, or saved preferences. If a newer supported release is found, NimBar opens its GitHub page; the app does not download or install it.

Automatic download and installation are not implemented. Recheck this document if that changes.

## Permissions

- **Accessibility:** reads exposed menu bar metadata and manages supported item visibility.
- **Screen Recording:** captures the menu bar strip used to display item images in Layout.
- **Input Monitoring:** may be needed when the live drag event filter cannot be installed through the existing permission state. It is used to protect the live drag gesture from native reordering; NimBar does not record typed keys.

NimBar does not request Full Disk Access. Permissions can be reviewed and revoked in **System Settings → Privacy & Security**.

## Storage and removal

Preferences and the icon cache are stored locally by macOS in NimBar's app preferences. Removing the app does not necessarily remove those preferences. Do not delete app data manually unless you understand that doing so removes the saved NimBar layout and settings.

## Contact

For ordinary privacy questions, use [GitHub Issues](https://github.com/emanuele0409/NimBar/issues) after the repository is public. Do not post personal or sensitive information there.
