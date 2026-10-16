// SPDX-License-Identifier: GPL-3.0-only
import AppKit

SettingsStore.migrateLegacyPreferences()
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
