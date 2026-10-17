// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    let safeMode: Bool
    @ObservedObject var accessibility: MenuBarAccessibility
    @ObservedObject var layout: MenuBarLayoutController
    @ObservedObject var updater: AppUpdateController
    @ObservedObject var loginItem: LoginItemController
    let quit: () -> Void

    private typealias SettingsSection = SettingsStore.SettingsSection
    private var colorScheme: ColorScheme { store.effectiveColorScheme }
    private var secondaryText: Color { NimBarAppearance.secondaryText(for: colorScheme) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 214)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: selectedSectionIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28, height: 28)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    Text(selectedSectionTitle)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 15)
                .padding(.bottom, 8)
                Group {
                    switch store.selectedSettingsSection ?? .general {
                    case .general: generalPanel
                    case .layout: layoutPanel
                    case .privacy: privacyPanel
                    case .about: aboutPanel
                    case .updates: updatesPanel
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background { WindowBlurBackground().ignoresSafeArea() }
        .foregroundStyle(NimBarAppearance.primaryText(for: colorScheme))
        .disabled(store.showPermissionSetup)
        .environment(\.colorScheme, store.effectiveColorScheme)
        .environment(\.locale, store.language.locale)
        .frame(minWidth: 900, minHeight: 620)
        .sheet(isPresented: $store.showsCreditsSheet) { creditsSheet }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image("NimBarLogo")
                .renderingMode(colorScheme == .dark ? .template : .original)
                .resizable().foregroundStyle(.white).scaledToFit()
                .frame(width: 126, height: 36, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 36)
                .padding(.bottom, 20)

            VStack(spacing: 9) {
                sidebarItem(.general, title: L10n.text("Generali"), symbol: "slider.horizontal.3", tint: .blue)
                sidebarItem(.layout, title: L10n.text("Layout"), symbol: "rectangle.3.group.fill", tint: .cyan)
                sidebarItem(.privacy, title: L10n.text("Privacy e sicurezza"), symbol: "hand.raised.fill", tint: .orange)
                sidebarItem(.about, title: L10n.text("Info"), symbol: "sparkles.rectangle.stack.fill", tint: .purple)
            }
            .padding(.horizontal, 12)
            Spacer(minLength: 12)
            VStack(spacing: 9) {
                sidebarItem(.updates, title: L10n.text("Aggiornamento"), symbol: "arrow.down.app.fill", tint: .green)
                Button(action: quit) {
                    HStack(spacing: 11) {
                        Image(systemName: "power.circle.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.red)
                            .frame(width: 26)
                        Text(L10n.text("Esci da NimBar"))
                            .font(.system(size: 12, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 11).frame(height: 42)
                    .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help(L10n.text("Esci da NimBar"))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
        }
        .frame(maxHeight: .infinity)
    }

    private func sidebarItem(_ section: SettingsSection, title: String, symbol: String, tint: Color) -> some View {
        let selected = store.selectedSettingsSection == section
        return Button { store.selectedSettingsSection = section } label: {
            HStack(spacing: 11) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selected ? .white : tint)
                    .frame(width: 30, height: 30)
                    .background(selected ? Color.white.opacity(0.18) : tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(title).font(.system(size: 12, weight: selected ? .semibold : .medium))
                    .lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                if selected { Circle().fill(.white.opacity(0.9)).frame(width: 5, height: 5) }
            }
            .padding(.horizontal, 9)
            .frame(height: 46)
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(LinearGradient(colors: colorScheme == .light ? [Color(red: 0.0, green: 0.32, blue: 0.76), Color(red: 0.0, green: 0.38, blue: 0.84)] : [Color.accentColor, Color.accentColor.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: Color.accentColor.opacity(0.20), radius: 7, y: 3)
                }
            }
            .foregroundStyle(selected ? Color.white : NimBarAppearance.primaryText(for: colorScheme))
        }
        .buttonStyle(.plain)
    }

    private var selectedSectionTitle: String {
        switch store.selectedSettingsSection ?? .general {
        case .general: L10n.text("Generali")
        case .layout: L10n.text("Layout")
        case .privacy: L10n.text("Privacy e sicurezza")
        case .about: L10n.text("Info")
        case .updates: L10n.text("Aggiornamento")
        }
    }

    private var selectedSectionIcon: String {
        switch store.selectedSettingsSection ?? .general {
        case .general: "slider.horizontal.3"
        case .layout: "rectangle.3.group.fill"
        case .privacy: "hand.raised.fill"
        case .about: "sparkles.rectangle.stack.fill"
        case .updates: "arrow.down.app.fill"
        }
    }

    private var creditsSheet: some View {
        VStack(spacing: 17) {
            Image("NimBarLogo").resizable().scaledToFit().frame(maxWidth: 250, maxHeight: 70)
            Text(L10n.text("Crediti e licenza")).font(.title2.weight(.bold))
            Text(L10n.text("Autore: Emanuele (emanuele0409)"))
                .font(.headline)
            Text(L10n.text("NimBar è un progetto open source distribuito secondo la licenza GPL-3.0-only."))
                .multilineTextAlignment(.center).foregroundStyle(secondaryText)
                .frame(maxWidth: 360)
            Link(destination: URL(string: "https://github.com/emanuele0409/NimBar")!) {
                Label(L10n.text("Visita il progetto su GitHub"), systemImage: "arrow.up.right.square")
            }
            Button(L10n.text("Chiudi")) { store.showsCreditsSheet = false }.keyboardShortcut(.cancelAction)
        }
        .padding(30).frame(minWidth: 420, minHeight: 310)
        .background(WindowBlurBackground().ignoresSafeArea())
    }

    private var generalPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            settingsCard(title: L10n.text("Aspetto e lingua"), symbol: "paintpalette.fill", tint: .purple) {
                HStack(spacing: 16) {
                    compactPicker(L10n.text("Lingua"), selection: $store.language) {
                        ForEach(AppLanguage.allCases) { language in Text(language.title).tag(language) }
                    }
                    compactPicker(L10n.text("Aspetto"), selection: $store.appearanceMode) {
                        ForEach(SettingsStore.AppearanceMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                }
            }

            settingsCard(title: L10n.text("Separatore nella barra dei menu"), symbol: "line.3.horizontal.decrease", tint: .blue) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.text("Combinazione modificatori")).font(.system(size: 12, weight: .medium))
                        Text(L10n.text("Tieni premuti questi tasti per mostrare il separatore e trascinare le icone."))
                            .font(.system(size: 10)).foregroundStyle(secondaryText).lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    Text(modifierTitle(store.hotKeyModifiers))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(.quaternary, in: Capsule())
                    Button(store.isCapturingHotKey ? L10n.text("Premi i tasti…") : L10n.text("Modifica")) {
                        store.isCapturingHotKey.toggle()
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    if store.isCapturingHotKey {
                        Button(L10n.text("Annulla")) { store.isCapturingHotKey = false }.controlSize(.small)
                        ModifierCaptureView { modifiers in
                            store.hotKeyModifiers = modifiers
                            store.isCapturingHotKey = false
                        }
                        .frame(width: 1, height: 1).opacity(0.01)
                    }
                }
                if store.liveEditorAccessUnavailable {
                    HStack(spacing: 8) {
                        Label(L10n.text("Il filtro del mouse non è disponibile. Abilita NimBar nei permessi richiesti per usare il separatore senza riordinare le icone."), systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 10)).foregroundStyle(NimBarAppearance.warning(for: colorScheme)).lineLimit(2)
                        Button(L10n.text("Permessi richiesti")) { store.showPermissionSetup = true }.controlSize(.small)
                    }
                }
            }

            settingsCard(title: L10n.text("Nascondimento automatico"), symbol: "clock.arrow.circlepath", tint: .teal) {
                HStack(spacing: 12) {
                    Toggle(L10n.text("Nascondimento automatico"), isOn: $store.autoHideEnabled)
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    Text(L10n.text("Nascondimento automatico")).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(L10n.text("Intervallo")).font(.system(size: 11)).foregroundStyle(secondaryText)
                    Picker(L10n.text("Intervallo"), selection: $store.autoHideDelay) {
                        ForEach(SettingsStore.AutoHideDelay.allCases) { delay in Text(delay.title).tag(delay) }
                    }
                    .labelsHidden().frame(width: 125).controlSize(.small).disabled(!store.autoHideEnabled)
                }
                Text(L10n.text("Il timer parte quando mostri le icone e resta in pausa mentre il puntatore è sulla barra dei menu."))
                    .font(.system(size: 10)).foregroundStyle(secondaryText).fixedSize(horizontal: false, vertical: true)
            }

            settingsCard(title: L10n.text("Avvio e barra dei menu"), symbol: "menubar.rectangle", tint: .indigo) {
                Toggle(L10n.text("Avvia NimBar al login"), isOn: Binding(
                    get: { loginItem.isRegistered }, set: { loginItem.setEnabled($0) }
                )).controlSize(.small)
                if loginItem.needsApproval {
                    HStack {
                        Text(L10n.text("Autorizza NimBar negli elementi di login per completare l’attivazione."))
                            .font(.system(size: 10)).foregroundStyle(secondaryText)
                        Spacer()
                        Button(L10n.text("Apri Elementi login")) { loginItem.openSystemSettings() }.controlSize(.small)
                    }
                }
                if let error = loginItem.errorDescription {
                    Text(L10n.format("Impossibile aggiornare l’avvio al login: %@", error))
                        .font(.system(size: 10)).foregroundStyle(.red)
                }
                Divider().opacity(0.45)
                Toggle(L10n.text("Nascondi l’icona NimBar dalla barra dei menu"), isOn: $store.hideNimBarIcon)
                    .controlSize(.small)
                Text(L10n.text("L’icona resta nascosta anche quando mostri le altre app. Per accedere a NimBar, fai clic destro su uno spazio vuoto della barra oppure riapri l’app da Applicazioni."))
                    .font(.system(size: 10)).foregroundStyle(secondaryText).fixedSize(horizontal: false, vertical: true)
            }
            if safeMode {
                Label(L10n.text("Modalità sicura attiva"), systemImage: "checkmark.shield.fill")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(NimBarAppearance.success(for: colorScheme))
            }
        }
        .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 12)
    }

    private func settingsCard<Content: View>(title: String, symbol: String, tint: Color,
                                             @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(tint)
                Text(title).font(.system(size: 11, weight: .semibold))
                Spacer()
            }
            content()
        }
        .padding(.horizontal, 13).padding(.vertical, 9)
        .modifier(NimBarCardSurface())
    }

    private func compactPicker<Selection: Hashable, Content: View>(_ title: String,
        selection: Binding<Selection>, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(secondaryText)
            Picker(title, selection: selection, content: content).labelsHidden().controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var layoutPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            settingsCard(title: L10n.text("Icona barra menu"), symbol: "menubar.rectangle", tint: .cyan) {
                HStack(spacing: 10) {
                    Text(L10n.text("Scegli il simbolo mostrato nella barra macOS."))
                        .font(.system(size: 11)).foregroundStyle(secondaryText)
                    Spacer(minLength: 4)
                    Menu {
                        ForEach(SettingsStore.MenuBarIconStyle.allCases) { style in
                            Button { store.menuBarIconStyle = style } label: {
                                Label { Text(style.title) } icon: { menuIconSymbol(style) }
                            }
                            .accessibilityLabel(style.title)
                            .accessibilityAddTraits(store.menuBarIconStyle == style ? .isSelected : [])
                        }
                    } label: {
                        HStack(spacing: 6) {
                            menuIconSymbol(store.menuBarIconStyle)
                            Text(store.menuBarIconStyle.title)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .controlSize(.small)
                    .menuStyle(.borderlessButton)
                }
            }
            HStack {
                Label(layout.isNativeBackendAvailable ? L10n.text("Barra nativa pronta") : L10n.text("Backend non disponibile"), systemImage: layout.isNativeBackendAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(layout.isNativeBackendAvailable ? NimBarAppearance.success(for: colorScheme) : NimBarAppearance.warning(for: colorScheme))
                Spacer()
                Button(layout.isCollapsed ? L10n.text("Mostra icone") : L10n.text("Nascondi icone")) { layout.toggleHiddenSection() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(!layout.hasHiddenItems)
            }
            settingsCard(title: L10n.text("BARRA DEI MENU"), symbol: "rectangle.split.3x1.fill", tint: .blue) {
                Text(L10n.text("Trascina un’icona nella sezione desiderata. Le modifiche si applicano subito."))
                    .font(.system(size: 10)).foregroundStyle(secondaryText)
                // Keep all three drop zones and both dividers mounted even
                // while AX returns an empty snapshot or refreshes the list.
                LayoutBoard(language: store.language, candidates: layoutCandidates, access: accessibility, layout: layout)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { accessibility.startLiveUpdates() }
        .onDisappear { accessibility.stopLiveUpdates() }
    }

    @ViewBuilder
    private func menuIconSymbol(_ style: SettingsStore.MenuBarIconStyle) -> some View {
        Group {
            switch style {
            case .original:
                Image(nsImage: originalMenuIconPreview)
                    .resizable().renderingMode(.template).scaledToFit()
            case .chevron:
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
            case .chevronDown:
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
            case .dot:
                Image(systemName: "circle.fill")
                    .font(.system(size: 4, weight: .regular))
            }
        }
        .frame(width: 16, height: 16)
        .fixedSize()
        .clipped()
        .foregroundStyle(.primary)
    }

    private var originalMenuIconPreview: NSImage {
        // Native macOS menus extract NSImage's point size and can ignore
        // SwiftUI frame modifiers. Bound a copy, preserving the full-resolution
        // representation and leaving the shared menu-bar artwork untouched.
        let image = (NSImage(named: "NimBarMenuBarMark")?.copy() as? NSImage)
            ?? NSImage(size: NSSize(width: 16, height: 16))
        let longestEdge = max(image.size.width, image.size.height)
        if longestEdge > 0 {
            let scale = 16 / longestEdge
            image.size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        }
        image.isTemplate = true
        return image
    }

    private var privacyPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            settingsCard(title: L10n.text("Permessi richiesti"), symbol: "checkmark.shield.fill", tint: .green) {
                permissionRow(title: L10n.text("Accessibilità"), allowed: accessibility.isTrusted)
                if !accessibility.isTrusted {
                    Button(L10n.text("Apri Accessibilità in Impostazioni…")) { accessibility.openAccessibilitySettings() }.controlSize(.small)
                }
                Divider().opacity(0.4)
                permissionRow(title: L10n.text("Registrazione schermo"), allowed: accessibility.hasScreenCaptureAccess)
                if !accessibility.hasScreenCaptureAccess {
                    Button(L10n.text("Apri Registrazione schermo in Impostazioni…")) { accessibility.openScreenCaptureSettings() }.controlSize(.small)
                }
                if accessibility.screenCaptureMayNeedRelaunch {
                    Text(L10n.text("Se hai appena autorizzato NimBar ma il permesso non risulta ancora attivo, chiudi e riapri l’app: macOS potrebbe applicare Registrazione schermo al riavvio."))
                        .font(.system(size: 10)).foregroundStyle(secondaryText).fixedSize(horizontal: false, vertical: true)
                }
                if accessibility.needsInputAccess {
                    Divider().opacity(0.4)
                    Text(L10n.text("Necessario per proteggere il trascinamento dal riordino di macOS"))
                        .font(.system(size: 10)).foregroundStyle(secondaryText)
                    Button(L10n.text("Apri Monitoraggio input"), action: accessibility.openInputMonitoringSettings).controlSize(.small)
                }
                Button(L10n.text("Benvenuto e permessi…")) { store.showPermissionSetup = true }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
            settingsCard(title: L10n.text("Dati e privacy"), symbol: "hand.raised.square.on.square.fill", tint: .blue) {
                Text(L10n.text("NimBar acquisisce localmente solo la fascia della barra menu per mostrare le icone reali. Le immagini restano in memoria e non vengono salvate né inviate. Non richiede Input Monitoring o Full Disk Access."))
                    .font(.system(size: 12)).foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 14)
    }

    private func permissionRow(title: String, allowed: Bool) -> some View {
        HStack(spacing: 9) {
            Image(systemName: allowed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(allowed ? NimBarAppearance.success(for: colorScheme) : NimBarAppearance.warning(for: colorScheme))
                .font(.system(size: 15))
            Text(title).font(.system(size: 12, weight: .medium))
            Spacer()
            Text(allowed ? L10n.text("Autorizzata") : L10n.text("Non autorizzata"))
                .font(.system(size: 10, weight: .medium)).foregroundStyle(allowed ? NimBarAppearance.success(for: colorScheme) : secondaryText)
        }
    }

    private var aboutPanel: some View {
        VStack(spacing: 13) {
            VStack(spacing: 11) {
                Image("NimBarLogo")
                    .renderingMode(colorScheme == .dark ? .template : .original)
                    .resizable().foregroundStyle(.white).scaledToFit()
                    .frame(maxWidth: 285, maxHeight: 72)
                Text(L10n.text("La barra dei menu, finalmente in ordine."))
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(secondaryText)
                    .multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    Label("NimBar", systemImage: "menubar.rectangle")
                    Text("•").foregroundStyle(.tertiary)
                    Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.1") beta")
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [Color.accentColor.opacity(0.14), Color.purple.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }

            settingsCard(title: L10n.text("Descrizione"), symbol: "text.alignleft", tint: .blue) {
                Text(L10n.text("NimBar organizza la barra dei menu di macOS: puoi nascondere le icone che usi meno, mostrarle su richiesta e configurare il comportamento del separatore trascinabile. La gestione avviene localmente sul Mac."))
                    .font(.system(size: 12)).foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 11) {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.text("Sviluppatore")).font(.system(size: 10)).foregroundStyle(secondaryText)
                        Text("emanuele0409").font(.system(size: 12, weight: .semibold))
                    }
                } icon: {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 22)).foregroundStyle(.purple)
                }
                Spacer()
                Button { store.showsCreditsSheet = true } label: {
                    Label(L10n.text("Crediti e licenza"), systemImage: "heart.text.square.fill")
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
            }
            .padding(13)
            .modifier(NimBarCardSurface())
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 14)
    }

    private var updatesPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            settingsCard(title: updater.statusTitle, symbol: updater.isConfigured ? "arrow.triangle.2.circlepath.circle.fill" : "sparkles", tint: .blue) {
                Text(updater.statusDetail).font(.system(size: 12)).foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button(updater.primaryActionTitle) {
                        Task { await updater.performPrimaryAction() }
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(!updater.canPerformPrimaryAction)
                    if updater.isWorking { ProgressView().controlSize(.small) }
                    Spacer()
                    Link(destination: updater.releasesURL) {
                        Label(L10n.text("Apri GitHub Releases"), systemImage: "arrow.up.right.square")
                    }.font(.system(size: 11))
                }
                if let date = updater.lastCheckDate {
                    Text(L10n.format("Ultima verifica: %@", date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(store.language.locale))))
                        .font(.system(size: 10)).foregroundStyle(secondaryText)
                }
            }
            settingsCard(title: L10n.text("Modalità di aggiornamento"), symbol: "gearshape.2.fill", tint: .indigo) {
                Picker(L10n.text("Aggiornamenti"), selection: $store.updateMode) {
                    ForEach(SettingsStore.UpdateMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                            .disabled(mode == .installAutomatically && !updater.supportsAutomaticInstallation)
                    }
                }.controlSize(.small)
                Text(store.updateMode.detail).font(.system(size: 11)).foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if !updater.supportsAutomaticInstallation {
                    Text(L10n.text("Il controllo automatico è disponibile. Download e installazione automatici saranno attivati solo quando i pacchetti potranno essere verificati con una firma sicura."))
                        .font(.system(size: 10)).foregroundStyle(secondaryText)
                }
                if !updater.isConfigured {
                    Text(L10n.text("La scelta viene salvata e sarà utilizzata quando sarà collegata la fonte degli aggiornamenti."))
                        .font(.system(size: 10)).foregroundStyle(secondaryText)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 14)
    }

    private var layoutCandidates: [MenuBarCandidate] {
        let candidates = accessibility.items
            .filter { !$0.isLiveDivider && accessibility.hasUsableLayoutIdentity($0) }
            .sorted { $0.x < $1.x }
        // Control Center and SystemUIServer can both expose the same clock.
        // The rightmost clock is the one at the end of the native menu bar.
        let clockID = candidates.last(where: \.isClock)?.id
        return candidates.filter { !$0.isClock || $0.id == clockID }
    }

}

private func modifierTitle(_ value: Int) -> String {
    var parts: [String] = []
    if value & 4 != 0 { parts.append("⌃") }
    if value & 8 != 0 { parts.append("⇧") }
    if value & 1 != 0 { parts.append("⌘") }
    if value & 2 != 0 { parts.append("⌥") }
    return parts.isEmpty ? L10n.text("Nessuno") : parts.joined(separator: " + ")
}

private struct ModifierCaptureView: NSViewRepresentable {
    let onCapture: (Int) -> Void

    func makeNSView(context: Context) -> ModifierCaptureNSView {
        let view = ModifierCaptureNSView()
        view.onCapture = onCapture
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ view: ModifierCaptureNSView, context: Context) {
        view.onCapture = onCapture
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
    }
}

private final class ModifierCaptureNSView: NSView {
    var onCapture: ((Int) -> Void)?
    private var accumulatedModifiers = 0

    override var acceptsFirstResponder: Bool { true }

    override func flagsChanged(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var current = 0
        if flags.contains(.command) { current |= 1 }
        if flags.contains(.option) { current |= 2 }
        if flags.contains(.control) { current |= 4 }
        if flags.contains(.shift) { current |= 8 }
        if current == 0 {
            if accumulatedModifiers != 0 { onCapture?(accumulatedModifiers) }
            accumulatedModifiers = 0
        } else {
            accumulatedModifiers |= current
        }
    }
}

@MainActor
private final class LayoutBoardState: ObservableObject {
    @Published var dropPreview: LayoutDropPreview?
}

private struct LayoutBoard: View {
    @Environment(\.colorScheme) private var colorScheme
    private var secondaryText: Color { NimBarAppearance.secondaryText(for: colorScheme) }
    let language: AppLanguage
    let candidates: [MenuBarCandidate]
    @ObservedObject var access: MenuBarAccessibility
    @ObservedObject var layout: MenuBarLayoutController
    @StateObject private var state = LayoutBoardState()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Spacer()
                Text(L10n.format("%@ icone", String(candidates.count))).font(.caption2).foregroundStyle(secondaryText)
            }
            let iconSize = access.layoutIconPointSize
            let itemGap: CGFloat = 10
            let groupGap: CGFloat = 6
            let emptySlot: CGFloat = 18
            HStack(spacing: groupGap) {
                zoneContent(.alwaysHidden, iconSize: iconSize, itemGap: itemGap, emptySlot: emptySlot)
                divider(index: 0)
                zoneContent(.hidden, iconSize: iconSize, itemGap: itemGap, emptySlot: emptySlot)
                divider(index: 1)
                zoneContent(.visible, iconSize: iconSize, itemGap: itemGap, emptySlot: emptySlot)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42, alignment: .leading)
            .modifier(NimBarCardSurface(cornerRadius: 10))
            .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.78), value: previewIDs)
            .frame(height: 42)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func divider(index: Int) -> some View {
        Capsule()
            .fill(index == 0 ? Color.orange : Color.accentColor)
            .frame(width: 2, height: 22)
            .frame(width: 8, height: 32)
            .accessibilityLabel(index == 0 ? L10n.text("Separatore: Sempre nascoste e Nascoste") : L10n.text("Separatore: Nascoste e Visibili"))
            .help(index == 0 ? L10n.text("Sempre nascoste / Nascoste") : L10n.text("Nascoste / Visibili"))
    }

    @ViewBuilder
    private func zoneContent(_ zone: MenuBarLayoutZone, iconSize: CGFloat, itemGap: CGFloat, emptySlot: CGFloat) -> some View {
        let zoneCandidates = baseCandidates(in: zone)
        let previewIndex = state.dropPreview?.zone == zone ? state.dropPreview?.insertionIndex : nil
        HStack(spacing: itemGap) {
            if zoneCandidates.isEmpty {
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: emptySlot, height: 28)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                ForEach(Array(zoneCandidates.enumerated()), id: \.element.id) { index, candidate in
                    if previewIndex == index { dropMarker(iconSize: iconSize) }
                    iconView(for: candidate, size: iconSize)
                }
                if previewIndex == zoneCandidates.count { dropMarker(iconSize: iconSize) }
            }
        }
        .padding(.trailing, zoneCandidates.isEmpty ? 0 : itemGap)
        .frame(minWidth: zoneCandidates.isEmpty ? emptySlot : 0, minHeight: 32, alignment: .leading)
        .contentShape(Rectangle())
        .onDrop(of: [UTType.plainText], delegate: LayoutZoneDropDelegate(
            zone: zone,
            itemCount: zoneCandidates.count,
            itemPitch: iconSize + itemGap,
            preview: $state.dropPreview,
            onDrop: { identifier, targetZone in performDrop(identifier, into: targetZone) }
        ))
    }

    @ViewBuilder
    private func iconView(for candidate: MenuBarCandidate, size: CGFloat) -> some View {
        let icon = MenuBarIcon(candidate: candidate, image: access.layoutImage(for: candidate))
            .frame(width: max(size, access.layoutImage(for: candidate)?.size.width ?? size), height: 30)
            .contentShape(Rectangle())
            .help(displayName(for: candidate))
        if candidate.isSystemOwned {
            icon
        } else {
            icon.onDrag {
                let provider = NSItemProvider()
                provider.registerDataRepresentation(
                    forTypeIdentifier: UTType.plainText.identifier,
                    visibility: .ownProcess
                ) { completion in
                    completion(Data(candidate.id.utf8), nil)
                    return nil
                }
                return provider
            } preview: {
                MenuBarIcon(candidate: candidate, image: access.layoutImage(for: candidate))
                    .frame(width: max(20, size), height: max(20, size))
            }
        }
    }

    private func dropMarker(iconSize: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color.accentColor.opacity(0.16))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
            .frame(width: iconSize, height: iconSize)
    }

    private func displayName(for candidate: MenuBarCandidate) -> String {
        if candidate.isSystemOwned, !candidate.label.isEmpty, candidate.label != candidate.applicationName {
            return candidate.label
        }
        return candidate.applicationName
    }

    private var previewIDs: [String] {
        [MenuBarLayoutZone.alwaysHidden, .hidden, .visible].flatMap { zone in
            var ids = baseCandidates(in: zone).map(\.id)
            if let dropPreview = state.dropPreview, dropPreview.zone == zone {
                ids.insert("drop-\(zone.rawValue)-\(dropPreview.insertionIndex)", at: min(dropPreview.insertionIndex, ids.count))
            }
            return ids
        }
    }

    private func performDrop(_ identifier: String, into zone: MenuBarLayoutZone) {
        DispatchQueue.main.async {
            guard let candidate = candidates.first(where: { $0.id == identifier }) else {
                state.dropPreview = nil
                access.refresh()
                return
            }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                layout.move(candidate, to: zone, access: access)
                state.dropPreview = nil
            }
        }
    }

    private func baseCandidates(in zone: MenuBarLayoutZone) -> [MenuBarCandidate] {
        candidates.filter { candidate in
            if candidate.isSystemOwned { return zone == .visible }
            switch zone {
            case .visible: return !layout.isHidden(candidate)
            case .hidden: return layout.hiddenBundleIDs.contains(candidate.bundleIdentifier)
            case .alwaysHidden: return layout.isAlwaysHidden(candidate)
            }
        }
    }
}

private struct LayoutDropPreview: Equatable {
    let zone: MenuBarLayoutZone
    let insertionIndex: Int
}

enum NimBarAppearance {
    static func success(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0, green: 0.34, blue: 0.14) : .green
    }

    static func warning(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.50, green: 0.23, blue: 0) : .orange
    }

    static func primaryText(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.10, green: 0.12, blue: 0.16) : .primary
    }

    static func secondaryText(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.25, green: 0.28, blue: 0.32) : Color(nsColor: .secondaryLabelColor)
    }
}

private struct NimBarCardSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = 13

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape.fill(.thinMaterial)
                    .overlay { shape.fill(Color.white.opacity(colorScheme == .light ? 0.48 : 0)) }
            }
            .overlay(shape.stroke(Color.primary.opacity(colorScheme == .light ? 0.14 : 0.07)))
    }
}

struct WindowBlurBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        WindowVisualEffect()
            // A white translucent veil keeps text legible over dark or saturated
            // wallpaper while allowing the window's native blur to show through.
            .overlay(Color.white.opacity(colorScheme == .light ? 0.76 : 0))
            .allowsHitTesting(false)
    }
}

private struct WindowVisualEffect: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.appearance = NSAppearance(named: colorScheme == .light ? .aqua : .darkAqua)
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.appearance = NSAppearance(named: colorScheme == .light ? .aqua : .darkAqua)
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
    }
}

private struct LayoutZoneDropDelegate: DropDelegate {
    let zone: MenuBarLayoutZone
    let itemCount: Int
    let itemPitch: CGFloat
    @Binding var preview: LayoutDropPreview?
    let onDrop: (String, MenuBarLayoutZone) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.plainText])
    }

    func dropEntered(info: DropInfo) { updatePreview(at: info.location.x) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updatePreview(at: info.location.x)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if preview?.zone == zone {
            withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.82)) { preview = nil }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [UTType.plainText]).first else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
            guard let data, let identifier = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                    preview = nil
                }
                onDrop(identifier, zone)
            }
        }
        return true
    }

    private func updatePreview(at x: CGFloat) {
        let index = min(itemCount, max(0, Int(x / max(itemPitch, 1))))
        let newPreview = LayoutDropPreview(zone: zone, insertionIndex: index)
        guard preview != newPreview else { return }
        withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.82)) { preview = newPreview }
    }
}

private struct MenuBarIcon: View {
    let candidate: MenuBarCandidate
    let image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .interpolation(.high)
                    .renderingMode(image.isTemplate ? .template : .original)
                    .foregroundStyle(.primary)
            } else {
                Color.clear
            }
        }
        .help(candidate.label.isEmpty ? candidate.applicationName : candidate.label)
        .accessibilityLabel(candidate.label.isEmpty ? candidate.applicationName : candidate.label)
    }
}
