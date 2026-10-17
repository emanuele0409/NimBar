// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Combine
import SwiftUI
import AppKit
import ServiceManagement

@MainActor
final class SettingsStore: ObservableObject {
    static func migrateLegacyPreferences() {
        let current = UserDefaults.standard
        let marker = "didMigratePreferencesFromMenuLiteBundleID"
        guard !current.bool(forKey: marker),
              let legacy = UserDefaults(suiteName: "org.menulite.MenuLite") else { return }
        let keys = [
            "autoHideEnabled", "autoHideDelay", "loginItemEnabled", "menuBarIconStyle",
            "hideMenuLiteIconWhenCollapsed.v2", "nativeHiddenBundleIDs",
            "nativeAlwaysHiddenBundleIDs", "layoutConfigured"
        ]
        for key in keys where current.object(forKey: key) == nil {
            if let value = legacy.object(forKey: key) { current.set(value, forKey: key) }
        }
        current.set(true, forKey: marker)
    }

    @Published var showPermissionSetup = false
    @Published var showsCreditsSheet = false
    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
            L10n.language = language
            onLanguageChanged?()
        }
    }
    var hasLanguageSelection: Bool { defaults.string(forKey: Keys.language) != nil }
    func confirmLanguageChoice() { defaults.set(language.rawValue, forKey: Keys.language) }
    var onLanguageChanged: (() -> Void)?
    @Published var isCapturingHotKey = false
    @Published var liveEditorAccessUnavailable = false
    enum SettingsSection: Hashable { case general, layout, privacy, about, updates }
    @Published var selectedSettingsSection: SettingsSection? = .general
    enum UpdateMode: String, CaseIterable, Identifiable {
        case manual, checkAutomatically, installAutomatically
        var id: String { rawValue }
        var title: String {
            switch self {
            case .manual: L10n.text("Manuale")
            case .checkAutomatically: L10n.text("Cerca automaticamente")
            case .installAutomatically: L10n.text("Scarica e installa automaticamente")
            }
        }
        var detail: String {
            switch self {
            case .manual: L10n.text("Gli aggiornamenti vengono cercati solo quando premi Verifica aggiornamenti.")
            case .checkAutomatically: L10n.text("Ricerca all’avvio e ogni 24 ore. Scegli tu quando scaricare e installare.")
            case .installAutomatically: L10n.text("L’installazione automatica sarà disponibile quando NimBar potrà verificare in modo sicuro la firma dei pacchetti.")
            }
        }
    }
    @Published var updateMode: UpdateMode {
        didSet {
            defaults.set(updateMode.rawValue, forKey: Keys.updateMode)
            onUpdateModeChanged?()
        }
    }
    var lastUpdateCheckDate: Date? {
        get { defaults.object(forKey: Keys.lastUpdateCheckDate) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastUpdateCheckDate) }
    }
    @Published private(set) var effectiveColorScheme: ColorScheme = .light

    func updateEffectiveAppearance(_ appearance: NSAppearance) {
        let resolved: ColorScheme = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
        if effectiveColorScheme != resolved { effectiveColorScheme = resolved }
    }
    enum AppearanceMode: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var title: String {
            switch self {
            case .system: L10n.text("Modalità sistema")
            case .light: L10n.text("Modalità chiara")
            case .dark: L10n.text("Modalità scura")
            }
        }
        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }
    @Published var appearanceMode: AppearanceMode {
        didSet {
            defaults.set(appearanceMode.rawValue, forKey: Keys.appearanceMode)
            onAppearanceModeChanged?()
        }
    }
    @Published var hotKeyModifiers: Int {
        didSet { defaults.set(hotKeyModifiers, forKey: Keys.hotKeyModifiers) }
    }
    enum MenuBarIconStyle: String, CaseIterable, Identifiable {
        case original, chevron, chevronDown, dot
        var id: String { rawValue }
        var title: String {
            switch self {
            case .original: L10n.text("Icona originale")
            case .chevron: L10n.text("Chevron")
            case .chevronDown: L10n.text("Chevron giù")
            case .dot: L10n.text("Punto")
            }
        }
    }

    enum AutoHideDelay: Int, CaseIterable, Identifiable {
        case three = 3, five = 5, ten = 10, thirty = 30, never = 0
        var id: Int { rawValue }
        var title: String { self == .never ? L10n.text("Mai") : L10n.format("%@ secondi", String(rawValue)) }
    }
    @Published var autoHideEnabled: Bool { didSet { defaults.set(autoHideEnabled, forKey: Keys.autoHideEnabled) } }
    @Published var autoHideDelay: AutoHideDelay { didSet { defaults.set(autoHideDelay.rawValue, forKey: Keys.autoHideDelay) } }
    @Published var menuBarIconStyle: MenuBarIconStyle {
        didSet {
            defaults.set(menuBarIconStyle.rawValue, forKey: Keys.menuBarIconStyle)
            onMenuBarIconStyleChanged?()
        }
    }
    @Published var hideNimBarIcon: Bool {
        didSet {
            defaults.set(hideNimBarIcon, forKey: Keys.hideNimBarIcon)
            onMenuBarVisibilityChanged?()
        }
    }
    var onMenuBarIconStyleChanged: (() -> Void)?
    var onMenuBarVisibilityChanged: (() -> Void)?
    var onAppearanceModeChanged: (() -> Void)?
    var onUpdateModeChanged: (() -> Void)?
    private let defaults: UserDefaults
    private enum Keys {
        static let autoHideEnabled = "autoHideEnabled"
        static let autoHideDelay = "autoHideDelay"
        static let menuBarIconStyle = "menuBarIconStyle"
        static let hotKeyModifiers = "dividerHotKeyModifiers"
        static let appearanceMode = "nimbarAppearanceMode"
        static let language = "nimbarLanguage"
        static let updateMode = "nimbarUpdateMode"
        static let lastUpdateCheckDate = "nimbarLastUpdateCheckDate"
        // Keep the existing preference while making hiding independent of section state.
        static let hideNimBarIcon = "hideMenuLiteIconWhenCollapsed.v2"
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let initialLanguage = AppLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .english
        language = initialLanguage
        L10n.language = initialLanguage
        updateMode = UpdateMode(rawValue: defaults.string(forKey: Keys.updateMode) ?? "") ?? .manual
        autoHideEnabled = defaults.object(forKey: Keys.autoHideEnabled) as? Bool ?? false
        let raw = defaults.object(forKey: Keys.autoHideDelay) as? Int ?? AutoHideDelay.five.rawValue
        autoHideDelay = AutoHideDelay(rawValue: raw) ?? .five
        let storedIconStyle = defaults.string(forKey: Keys.menuBarIconStyle) ?? ""
        menuBarIconStyle = MenuBarIconStyle(rawValue: storedIconStyle) ?? .chevron
        hideNimBarIcon = defaults.object(forKey: Keys.hideNimBarIcon) as? Bool ?? false
        hotKeyModifiers = defaults.object(forKey: Keys.hotKeyModifiers) as? Int ?? 3
        appearanceMode = AppearanceMode(rawValue: defaults.string(forKey: Keys.appearanceMode) ?? "system") ?? .system
    }
}


@MainActor
protocol LoginItemServicing {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

@MainActor
private final class SystemLoginItemService: LoginItemServicing {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

/// System registration is the source of truth, including changes in System Settings.
@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var errorDescription: String?
    private let service: any LoginItemServicing

    var isRegistered: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }

    init(service: (any LoginItemServicing)? = nil) {
        self.service = service ?? SystemLoginItemService()
        refresh()
    }

    func refresh() { status = service.status }

    func setEnabled(_ enabled: Bool) {
        refresh()
        errorDescription = nil
        do {
            if enabled && !isRegistered {
                try service.register()
            } else if !enabled && isRegistered {
                try service.unregister()
            }
            refresh()
        } catch {
            // Reflect the real service even if registration succeeded but approval is pending.
            refresh()
            errorDescription = error.localizedDescription
        }
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
