// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Combine

struct AppUpdateRelease: Equatable, Sendable {
    let version: String
    let build: Int
    let assetURL: URL

    func isNewer(than version: String, build: Int) -> Bool {
        let order = self.version.compare(version, options: .numeric)
        return order == .orderedDescending || (order == .orderedSame && self.build > build)
    }
}

/// The GitHub integration will supply this service once the repository and
/// release artifact format are known. Installation must verify the downloaded
/// app's bundle ID, Apple signature and expected Team ID before replacement;
/// release-provided executables/scripts must never be run.
@MainActor
protocol AppUpdateService {
    func latestRelease() async throws -> AppUpdateRelease?
    func download(_ release: AppUpdateRelease) async throws -> URL
    func install(_ release: AppUpdateRelease, downloadedFile: URL) async throws
}

@MainActor
final class AppUpdateController: ObservableObject {
    enum State: Equatable {
        case unconfigured, idle, checking, upToDate
        case available(AppUpdateRelease)
        case downloading(AppUpdateRelease)
        case readyToInstall(AppUpdateRelease, URL)
        case installing(AppUpdateRelease)
        case installed(AppUpdateRelease)
        case failed(String)
    }

    @Published private(set) var state: State {
        didSet { onStateChanged?() }
    }
    @Published private(set) var lastCheckDate: Date?
    @Published private(set) var requestedWithoutSource = false
    var onStateChanged: (() -> Void)?
    private let settings: SettingsStore
    private let service: (any AppUpdateService)?
    private let currentVersion: String
    private let currentBuild: Int
    private let canInstallAutomatically: () -> Bool
    private var timer: Timer?
    private var operationInProgress = false
    static let checkInterval: TimeInterval = 24 * 60 * 60

    init(settings: SettingsStore, service: (any AppUpdateService)? = nil,
         currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0",
         currentBuild: Int = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0,
         canInstallAutomatically: @escaping () -> Bool = { false }) {
        self.settings = settings
        self.service = service
        self.currentVersion = currentVersion
        self.currentBuild = currentBuild
        self.canInstallAutomatically = canInstallAutomatically
        lastCheckDate = settings.lastUpdateCheckDate
        state = service == nil ? .unconfigured : .idle
    }

    var primaryActionTitle: String {
        switch state {
        case .available: L10n.text("Scarica e installa")
        case .readyToInstall: L10n.text("Installa e riavvia")
        case .checking: L10n.text("Verifica in corso…")
        case .downloading: L10n.text("Download in corso…")
        case .installing: L10n.text("Installazione in corso…")
        default: L10n.text("Verifica aggiornamenti")
        }
    }

    var canPerformPrimaryAction: Bool { !operationInProgress }
    var isConfigured: Bool { service != nil }
    var isWorking: Bool { operationInProgress }
    var statusTitle: String {
        switch state {
        case .unconfigured: L10n.text("Aggiornamenti non ancora configurati")
        case .idle: L10n.text("Verifica se è disponibile una nuova versione")
        case .checking: L10n.text("Ricerca degli aggiornamenti…")
        case .upToDate: L10n.text("NimBar è aggiornata")
        case .available(let release): L10n.format("È disponibile NimBar %@", release.version)
        case .downloading: L10n.text("Download dell’aggiornamento…")
        case .readyToInstall: L10n.text("Aggiornamento pronto per l’installazione")
        case .installing: L10n.text("Installazione dell’aggiornamento…")
        case .installed: L10n.text("Aggiornamento installato")
        case .failed: L10n.text("Impossibile completare l’aggiornamento")
        }
    }

    var statusDetail: String {
        switch state {
        case .unconfigured:
            requestedWithoutSource
                ? L10n.text("La verifica non può partire finché non viene collegata la pagina delle release GitHub. Le tue preferenze sono salvate.")
                : L10n.text("La pagina delle release GitHub verrà collegata in una prossima versione. Puoi già scegliere la modalità di aggiornamento.")
        case .readyToInstall:
            L10n.text("NimBar installerà l’aggiornamento quando le impostazioni saranno chiuse e nessun trascinamento sarà in corso. Puoi anche installarlo adesso.")
        case .failed(let message): message
        case .installed: L10n.text("NimBar verrà riavviata con la nuova versione.")
        default: L10n.format("Versione attuale: %@ beta (build %@).", currentVersion, String(currentBuild))
        }
    }

    func start() {
        // No timer, network or install activity without a configured source.
        guard service != nil, timer == nil else { return }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.automaticTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Task { await automaticTick() }
    }

    func preferencesDidChange() {
        Task { await automaticTick() }
    }

    func performPrimaryAction() async {
        guard !operationInProgress else { return }
        switch state {
        case .available(let release): await download(release, explicitlyInstall: true)
        case .readyToInstall(let release, let file): await install(release, file: file, explicit: true)
        default: await check()
        }
    }

    func automaticTick(at now: Date = Date()) async {
        guard service != nil, !operationInProgress, settings.updateMode != .manual else { return }
        if settings.updateMode == .installAutomatically {
            if case .readyToInstall(let release, let file) = state {
                await install(release, file: file, explicit: false)
                return
            }
            if case .available(let release) = state {
                await download(release, explicitlyInstall: false)
                return
            }
        }
        guard lastCheckDate.map({ now.timeIntervalSince($0) >= Self.checkInterval }) ?? true else { return }
        await check(at: now)
    }

    private func check(at now: Date = Date()) async {
        guard let service else {
            requestedWithoutSource = true
            state = .unconfigured
            return
        }
        operationInProgress = true
        state = .checking
        lastCheckDate = now
        settings.lastUpdateCheckDate = now
        do {
            let release = try await service.latestRelease()
            operationInProgress = false
            if let release, release.isNewer(than: currentVersion, build: currentBuild) {
                state = .available(release)
                if settings.updateMode == .installAutomatically {
                    await download(release, explicitlyInstall: false)
                }
            } else {
                state = .upToDate
            }
        } catch {
            operationInProgress = false
            state = .failed(error.localizedDescription)
        }
    }

    private func download(_ release: AppUpdateRelease, explicitlyInstall: Bool) async {
        guard let service, !operationInProgress else { return }
        operationInProgress = true
        state = .downloading(release)
        do {
            let file = try await service.download(release)
            operationInProgress = false
            state = .readyToInstall(release, file)
            if explicitlyInstall || settings.updateMode == .installAutomatically {
                await install(release, file: file, explicit: explicitlyInstall)
            }
        } catch {
            operationInProgress = false
            state = .failed(error.localizedDescription)
        }
    }

    private func install(_ release: AppUpdateRelease, file: URL, explicit: Bool) async {
        guard let service, !operationInProgress,
              explicit || (settings.updateMode == .installAutomatically && canInstallAutomatically()) else { return }
        operationInProgress = true
        state = .installing(release)
        do {
            try await service.install(release, downloadedFile: file)
            operationInProgress = false
            state = .installed(release)
        } catch {
            operationInProgress = false
            state = .failed(error.localizedDescription)
        }
    }
}
