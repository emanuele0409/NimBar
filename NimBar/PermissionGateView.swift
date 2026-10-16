// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import AppKit

struct PermissionGateView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var store: SettingsStore
    @ObservedObject var accessibility: MenuBarAccessibility
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image("NimBarLogo")
                .renderingMode(colorScheme == .dark ? .template : .original)
                .resizable().scaledToFit()
                .foregroundStyle(.white)
                .frame(maxWidth: 460, maxHeight: 104)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            VStack(spacing: 5) {
                Text(L10n.text("Benvenuti in NimBar"))
                    .font(.largeTitle.weight(.semibold))
                Text("emanuele0409")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            Text(L10n.text("NimBar ti aiuta a tenere ordinata la barra dei menu di macOS. Puoi nascondere le icone che usi meno e mostrarle di nuovo quando vuoi, con un separatore trascinabile e controlli rapidi."))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 9) {
                Text("Language / Lingua").font(.headline)
                Picker("Language / Lingua", selection: $store.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .labelsHidden().pickerStyle(.segmented).controlSize(.large)
                .frame(maxWidth: .infinity)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))

            permissionRow(
                title: L10n.text("Accessibilità"),
                detail: accessibility.isTrusted ? L10n.text("Autorizzata") : L10n.text("Necessaria per individuare e gestire le icone"),
                isGranted: accessibility.isTrusted,
                actionTitle: L10n.text("Apri Accessibilità"),
                action: accessibility.openAccessibilitySettings
            )
            permissionRow(
                title: L10n.text("Registrazione schermo"),
                detail: accessibility.hasScreenCaptureAccess ? L10n.text("Autorizzata") : L10n.text("Necessaria per mostrare le icone originali"),
                isGranted: accessibility.hasScreenCaptureAccess,
                actionTitle: L10n.text("Apri Registrazione schermo"),
                action: accessibility.openScreenCaptureSettings
            )
            if accessibility.screenCaptureMayNeedRelaunch {
                Text(L10n.text("Se hai appena autorizzato NimBar ma il permesso non risulta ancora attivo, chiudi e riapri l’app: macOS potrebbe applicare Registrazione schermo al riavvio."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            if accessibility.needsInputAccess {
                permissionRow(title: L10n.text("Monitoraggio input"),
                    detail: accessibility.hasInputAccess ? L10n.text("Autorizzata") : L10n.text("Necessario per proteggere il trascinamento dal riordino di macOS"),
                    isGranted: accessibility.hasInputAccess,
                    actionTitle: L10n.text("Apri Monitoraggio input"), action: accessibility.openInputMonitoringSettings)
            }

            Text(L10n.text("Per funzionare, NimBar ha bisogno di questi permessi. I pulsanti aprono la sezione corretta di Impostazioni di Sistema; abilita NimBar e poi torna qui."))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text(accessibility.message).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(accessibility.requiredPermissionsGranted ? L10n.text("Continua") : L10n.text("Più tardi"), action: dismiss)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(accessibility.requiredPermissionsGranted ? .accentColor : .secondary)
                    .frame(minWidth: accessibility.requiredPermissionsGranted ? 132 : 0,
                           minHeight: accessibility.requiredPermissionsGranted ? 42 : 0)
                    .keyboardShortcut(accessibility.requiredPermissionsGranted ? .defaultAction : .cancelAction)
            }
        }
        .padding(34)
        .frame(width: 740)
        .frame(minHeight: 680)
        .environment(\.locale, store.language.locale)
        .background {
            WelcomeBlurBackground().ignoresSafeArea()
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .fixedSize(horizontal: false, vertical: true)
    }

    private func permissionRow(title: String, detail: String, isGranted: Bool,
                               actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isGranted ? .green : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !isGranted {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct WelcomeBlurBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 24
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
    }
}
