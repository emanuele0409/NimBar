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

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 8) {
                List(selection: $store.selectedSettingsSection) {
                    Section("NimBar") {
                        Label(L10n.text("Generali"), systemImage: "gearshape").tag(SettingsSection.general)
                        Label(L10n.text("Layout"), systemImage: "rectangle.3.group").tag(SettingsSection.layout)
                        Label(L10n.text("Privacy e sicurezza"), systemImage: "lock.shield").tag(SettingsSection.privacy)
                        Label(L10n.text("Info"), systemImage: "info.circle").tag(SettingsSection.about)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(.ultraThinMaterial)
                Spacer(minLength: 0)
                Button { store.selectedSettingsSection = .updates } label: {
                    Label(L10n.text("Aggiornamento"), systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8).padding(.vertical, 7)
                        .foregroundStyle(store.selectedSettingsSection == .updates ? Color.white : Color.primary)
                        .background(store.selectedSettingsSection == .updates ? Color.accentColor : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                Button(action: quit) {
                    Label(L10n.text("Esci da NimBar"), systemImage: "power")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 176, max: 190)
        } detail: {
            Group {
                switch store.selectedSettingsSection ?? .general {
                case .general: generalPanel
                case .layout: layoutPanel
                case .privacy: privacyPanel
                case .about: aboutPanel
                case .updates: updatesPanel
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if colorScheme == .light {
                    Color.white
                } else {
                    Color(red: 0.10, green: 0.11, blue: 0.13)
                }
            }
            .foregroundStyle(.primary)
        }
        .disabled(store.showPermissionSetup)
        .navigationSplitViewStyle(.balanced)
        // AppKit owns the appearance. A preferredColorScheme presentation
        // override can stick to NSWindow when the preference returns to nil.
        .environment(\.colorScheme, store.effectiveColorScheme)
        .environment(\.locale, store.language.locale)
        .frame(minWidth: 900, minHeight: 620)

    }

    private var generalPanel: some View {
        Form {
            Image("NimBarLogo")
                .renderingMode(colorScheme == .dark ? .template : .original)
                .resizable()
                .foregroundStyle(.white)
                .scaledToFit()
                .frame(maxWidth: 390, maxHeight: 96)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            Picker(L10n.text("Lingua"), selection: $store.language) {
                ForEach(AppLanguage.allCases) { language in Text(language.title).tag(language) }
            }
            Picker(L10n.text("Aspetto"), selection: $store.appearanceMode) {
                ForEach(SettingsStore.AppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            Section(L10n.text("Separatore nella barra dei menu")) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.text("Combinazione modificatori"))
                        Text(L10n.text("Tieni premuti questi tasti per mostrare il separatore e trascinare le icone."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(modifierTitle(store.hotKeyModifiers))
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.quaternary, in: Capsule())
                    Button(store.isCapturingHotKey ? L10n.text("Premi i tasti…") : L10n.text("Modifica")) {
                        store.isCapturingHotKey.toggle()
                    }
                    .buttonStyle(.borderedProminent)
                    if store.isCapturingHotKey {
                        Button(L10n.text("Annulla")) { store.isCapturingHotKey = false }
                        ModifierCaptureView { modifiers in
                            store.hotKeyModifiers = modifiers
                            store.isCapturingHotKey = false
                        }
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                    }
                }
            }
            if store.liveEditorAccessUnavailable {
                Text(L10n.text("Il filtro del mouse non è disponibile. Abilita NimBar nei permessi richiesti per usare il separatore senza riordinare le icone."))
                    .font(.callout).foregroundStyle(.orange)
                Button(L10n.text("Permessi richiesti")) { store.showPermissionSetup = true }
            }
            Toggle(L10n.text("Nascondimento automatico"), isOn: $store.autoHideEnabled)
            Picker(L10n.text("Intervallo"), selection: $store.autoHideDelay) {
                ForEach(SettingsStore.AutoHideDelay.allCases) { delay in Text(delay.title).tag(delay) }
            }
            Section(L10n.text("Avvio e barra dei menu")) {
                Toggle(L10n.text("Avvia NimBar al login"), isOn: Binding(
                    get: { loginItem.isRegistered }, set: { loginItem.setEnabled($0) }
                ))
                if loginItem.needsApproval {
                    Text(L10n.text("Autorizza NimBar negli elementi di login per completare l’attivazione."))
                        .font(.caption).foregroundStyle(.secondary)
                    Button(L10n.text("Apri Elementi login")) { loginItem.openSystemSettings() }
                }
                if let error = loginItem.errorDescription {
                    Text(L10n.format("Impossibile aggiornare l’avvio al login: %@", error))
                        .font(.caption).foregroundStyle(.red)
                }
                Toggle(L10n.text("Nascondi l’icona NimBar dalla barra dei menu"), isOn: $store.hideNimBarIcon)
                Text(L10n.text("L’icona resta nascosta anche quando mostri le altre app. Per accedere a NimBar, fai clic destro su uno spazio vuoto della barra oppure riapri l’app da Applicazioni."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(L10n.text("Il timer parte quando mostri le icone e resta in pausa mentre il puntatore è sulla barra dei menu."))
                .font(.caption).foregroundStyle(.secondary)
            Text(L10n.text("Tieni premuta la combinazione scelta per mostrare il separatore nella barra dei menu; trascina un’icona attraverso la linea per nasconderla o mostrarla."))
                .font(.caption).foregroundStyle(.secondary)
            if safeMode { Label(L10n.text("Modalità sicura attiva"), systemImage: "checkmark.shield") }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(24)
        .navigationTitle(L10n.text("Generali"))
    }

    private var layoutPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.text("Icona barra menu"))
                    Menu {
                        ForEach(SettingsStore.MenuBarIconStyle.allCases) { style in
                            Button {
                                store.menuBarIconStyle = style
                            } label: {
                                Label {
                                    Text(style.title)
                                } icon: {
                                    menuIconSymbol(style)
                                }
                            }
                            .accessibilityLabel(style.title)
                            .accessibilityAddTraits(store.menuBarIconStyle == style ? .isSelected : [])
                        }
                    } label: {
                        HStack(spacing: 7) {
                            menuIconSymbol(store.menuBarIconStyle)
                            Text(store.menuBarIconStyle.title)
                        }
                    }
                }
                HStack {
                    Spacer()
                    Label(layout.isNativeBackendAvailable ? L10n.text("Barra nativa pronta") : L10n.text("Backend non disponibile"), systemImage: layout.isNativeBackendAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(layout.isNativeBackendAvailable ? .green : .orange)
                    Button(layout.isCollapsed ? L10n.text("Mostra icone") : L10n.text("Nascondi icone")) { layout.toggleHiddenSection() }
                        .disabled(!layout.hasHiddenItems)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.text("Trascina un’icona nella sezione desiderata. Le modifiche si applicano subito."))
                        .font(.caption).foregroundStyle(.secondary)
                    // Keep all three drop zones and both dividers mounted even
                    // while AX returns an empty snapshot or refreshes the list.
                    LayoutBoard(language: store.language, candidates: layoutCandidates, access: accessibility, layout: layout)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(L10n.text("Layout"))
        .onAppear { accessibility.startLiveUpdates() }
        .onDisappear { accessibility.stopLiveUpdates() }
    }

    @ViewBuilder
    private func menuIconSymbol(_ style: SettingsStore.MenuBarIconStyle) -> some View {
        Group {
            switch style {
            case .original:
                Image("NimBarMenuBarMark")
                    .resizable().renderingMode(.template).scaledToFit()
                    .frame(width: 16, height: 16)
            case .chevron:
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 16, height: 16)
            case .chevronDown:
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 16, height: 16)
            case .dot:
                Image(systemName: "circle.fill")
                    .font(.system(size: 4, weight: .regular))
                    .frame(width: 16, height: 16)
            }
        }
        .foregroundStyle(.primary)
    }

    private var privacyPanel: some View {
        Form {
                Section(L10n.text("Permessi richiesti")) {
                    Button(L10n.text("Benvenuto e permessi…")) { store.showPermissionSetup = true }
                    LabeledContent(L10n.text("Accessibilità"), value: accessibility.isTrusted ? L10n.text("Autorizzata") : L10n.text("Non autorizzata"))
                    LabeledContent(L10n.text("Registrazione schermo"), value: accessibility.hasScreenCaptureAccess ? L10n.text("Autorizzata") : L10n.text("Non autorizzata"))
                    Text(L10n.text("Serve per leggere le icone esposte dalle app. Il nascondimento parte solo dopo un trascinamento esplicito nell’editor Layout."))
                        .font(.callout).foregroundStyle(.secondary)
                    if !accessibility.isTrusted {
                        Button(L10n.text("Apri Accessibilità in Impostazioni…")) { accessibility.openAccessibilitySettings() }
                    }
                    if !accessibility.hasScreenCaptureAccess {
                        Button(L10n.text("Apri Registrazione schermo in Impostazioni…")) { accessibility.openScreenCaptureSettings() }
                    }
                    if accessibility.screenCaptureMayNeedRelaunch {
                        Text(L10n.text("Se hai appena autorizzato NimBar ma il permesso non risulta ancora attivo, chiudi e riapri l’app: macOS potrebbe applicare Registrazione schermo al riavvio.")).font(.callout).foregroundStyle(.secondary)
                    }
                }
                if accessibility.needsInputAccess {
                    Section(L10n.text("Monitoraggio input")) {
                        Text(L10n.text("Necessario per proteggere il trascinamento dal riordino di macOS"))
                        Button(L10n.text("Apri Monitoraggio input"), action: accessibility.openInputMonitoringSettings)
                    }
                }
                Section(L10n.text("Dati")) {
                    Text(L10n.text("NimBar acquisisce localmente solo la fascia della barra menu per mostrare le icone reali. Le immagini restano in memoria e non vengono salvate né inviate. Non richiede Input Monitoring o Full Disk Access."))
                        .font(.callout).foregroundStyle(.secondary)
                }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(24)
        .navigationTitle(L10n.text("Privacy e sicurezza"))
    }

    private var aboutPanel: some View {
        Form {
                LabeledContent(L10n.text("Applicazione"), value: "NimBar")
                LabeledContent(L10n.text("Sviluppatore"), value: "emanuele0409")
                LabeledContent(L10n.text("Versione"), value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0") beta")
                Section(L10n.text("Descrizione")) {
                    Text(L10n.text("NimBar organizza la barra dei menu di macOS: puoi nascondere le icone che usi meno, mostrarle su richiesta e configurare il comportamento del separatore trascinabile. La gestione avviene localmente sul Mac."))
                        .fixedSize(horizontal: false, vertical: true)
                }
                LabeledContent(L10n.text("Licenza"), value: "GPL-3.0-only")
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(24)
        .navigationTitle(L10n.text("Info"))
    }

    private var updatesPanel: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label(updater.statusTitle, systemImage: updater.isConfigured ? "arrow.triangle.2.circlepath" : "info.circle")
                        .font(.headline)
                    Text(updater.statusDetail)
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        Button(updater.primaryActionTitle) {
                            Task { await updater.performPrimaryAction() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!updater.canPerformPrimaryAction)
                        if updater.isWorking { ProgressView().controlSize(.small) }
                    }
                    Link(destination: updater.releasesURL) {
                        Label(L10n.text("Apri GitHub Releases"), systemImage: "arrow.up.right.square")
                    }
                    if let date = updater.lastCheckDate {
                        Text(L10n.format("Ultima verifica: %@", date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(store.language.locale))))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
            Section(L10n.text("Modalità di aggiornamento")) {
                Picker(L10n.text("Aggiornamenti"), selection: $store.updateMode) {
                    ForEach(SettingsStore.UpdateMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                            .disabled(mode == .installAutomatically && !updater.supportsAutomaticInstallation)
                    }
                }
                Text(store.updateMode.detail)
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !updater.supportsAutomaticInstallation {
                    Text(L10n.text("Il controllo automatico è disponibile. Download e installazione automatici saranno attivati solo quando i pacchetti potranno essere verificati con una firma sicura.")).font(.caption).foregroundStyle(.secondary)
                }
                if !updater.isConfigured {
                    Text(L10n.text("La scelta viene salvata e sarà utilizzata quando sarà collegata la fonte degli aggiornamenti."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(24)
        .navigationTitle(L10n.text("Aggiornamento"))
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

private struct LayoutBoard: View {
    let language: AppLanguage
    let candidates: [MenuBarCandidate]
    @ObservedObject var access: MenuBarAccessibility
    @ObservedObject var layout: MenuBarLayoutController
    @State private var dropPreview: LayoutDropPreview?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.text("BARRA DEI MENU")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(L10n.format("%@ icone", String(candidates.count))).font(.caption2).foregroundStyle(.tertiary)
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
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.08)))
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
        let previewIndex = dropPreview?.zone == zone ? dropPreview?.insertionIndex : nil
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
            preview: $dropPreview,
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
            if let dropPreview, dropPreview.zone == zone {
                ids.insert("drop-\(zone.rawValue)-\(dropPreview.insertionIndex)", at: min(dropPreview.insertionIndex, ids.count))
            }
            return ids
        }
    }

    private func performDrop(_ identifier: String, into zone: MenuBarLayoutZone) {
        DispatchQueue.main.async {
            guard let candidate = candidates.first(where: { $0.id == identifier }) else {
                dropPreview = nil
                access.refresh()
                return
            }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                layout.move(candidate, to: zone, access: access)
                dropPreview = nil
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
