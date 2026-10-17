// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Foundation
import Combine

struct AppUpdateRelease: Equatable, Sendable {
    let version: String
    let build: Int
    let assetURL: URL
    let releaseURL: URL?
    let isPrerelease: Bool

    init(version: String, build: Int, assetURL: URL, releaseURL: URL? = nil, isPrerelease: Bool = false) {
        self.version = version
        self.build = build
        self.assetURL = assetURL
        self.releaseURL = releaseURL
        self.isPrerelease = isPrerelease
    }

    func isNewer(than version: String, build: Int, isPrerelease currentIsPrerelease: Bool = false) -> Bool {
        let order = self.version.compare(version, options: .numeric)
        if order == .orderedDescending { return true }
        guard order == .orderedSame else { return false }
        if isPrerelease != currentIsPrerelease { return !isPrerelease }
        return self.build > build
    }

    func isNewer(than other: AppUpdateRelease) -> Bool {
        let order = version.compare(other.version, options: .numeric)
        if order != .orderedSame { return order == .orderedDescending }
        if isPrerelease != other.isPrerelease { return !isPrerelease }
        return build > other.build
    }
}

@MainActor
protocol AppUpdateService {
    var supportsAutomaticInstallation: Bool { get }
    func latestRelease() async throws -> AppUpdateRelease?
    func download(_ release: AppUpdateRelease) async throws -> URL
    func install(_ release: AppUpdateRelease, downloadedFile: URL) async throws
    func openReleasePage(_ release: AppUpdateRelease)
}

extension AppUpdateService {
    var supportsAutomaticInstallation: Bool { true }
    func openReleasePage(_ release: AppUpdateRelease) {
        if let url = release.releaseURL { NSWorkspace.shared.open(url) }
    }
}

enum GitHubReleaseServiceError: LocalizedError {
    case invalidResponse
    case noSupportedReleaseFormat
    case automaticInstallationUnavailable
    case githubResponse(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: L10n.text("Risposta GitHub non valida.")
        case .noSupportedReleaseFormat: L10n.text("La release GitHub non usa un formato di versione supportato.")
        case .automaticInstallationUnavailable:
            L10n.text("L’installazione automatica richiede pacchetti firmati e verificabili. Apri la release GitHub per scaricare manualmente.")
        case .githubResponse(let status): L10n.format("GitHub ha restituito l’errore HTTP %@.", String(status))
        }
    }
}

/// Read-only client for public, published GitHub Releases. It never downloads
/// or replaces an application bundle; release assets are opened in the browser.
@MainActor
final class GitHubReleaseService: AppUpdateService {
    static let releasesURL = URL(string: "https://github.com/emanuele0409/NimBar/releases")!
    private static let apiURL = URL(string: "https://api.github.com/repos/emanuele0409/NimBar/releases?per_page=30")!
    private let session: URLSession
    private let allowsPrereleases: Bool

    var supportsAutomaticInstallation: Bool { false }

    init(session: URLSession = .shared,
         allowsPrereleases: Bool = Bundle.main.infoDictionary?["NIMBARReleaseChannel"] as? String != "stable") {
        self.session = session
        self.allowsPrereleases = allowsPrereleases
    }

    func latestRelease() async throws -> AppUpdateRelease? {
        var request = URLRequest(url: Self.apiURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("NimBar", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw GitHubReleaseServiceError.invalidResponse
        }
        guard response.statusCode == 200 else {
            throw GitHubReleaseServiceError.githubResponse(response.statusCode)
        }

        let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
        guard !releases.isEmpty else { return nil }
        let candidates = releases.compactMap(Self.makeAppRelease)
            .filter { allowsPrereleases || !$0.isPrerelease }
        guard let newest = candidates.reduce(Optional<AppUpdateRelease>.none, { newest, candidate in
            guard let newest else { return candidate }
            return candidate.isNewer(than: newest) ? candidate : newest
        }) else { throw GitHubReleaseServiceError.noSupportedReleaseFormat }
        return newest
    }

    func download(_ release: AppUpdateRelease) async throws -> URL {
        throw GitHubReleaseServiceError.automaticInstallationUnavailable
    }

    func install(_ release: AppUpdateRelease, downloadedFile: URL) async throws {
        throw GitHubReleaseServiceError.automaticInstallationUnavailable
    }

    func openReleasePage(_ release: AppUpdateRelease) {
        NSWorkspace.shared.open(release.releaseURL ?? Self.releasesURL)
    }

    private static func makeAppRelease(_ release: GitHubRelease) -> AppUpdateRelease? {
        guard !release.draft,
              let releaseURL = URL(string: release.htmlURL),
              releaseURL.scheme == "https",
              releaseURL.host == "github.com",
              releaseURL.path.hasPrefix("/emanuele0409/NimBar/releases/") else { return nil }

        // Supported tags: vMAJOR.MINOR.PATCH and vMAJOR.MINOR.PATCH-beta.BUILD.
        let pattern = #"^v?(\d+\.\d+\.\d+)(?:-beta\.(\d+))?$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: release.tagName,
                                                range: NSRange(release.tagName.startIndex..<release.tagName.endIndex, in: release.tagName)),
              let versionRange = Range(match.range(at: 1), in: release.tagName) else { return nil }
        let version = String(release.tagName[versionRange])
        let buildRange = Range(match.range(at: 2), in: release.tagName)
        let tagBuild = buildRange.flatMap { Int(release.tagName[$0]) }
        guard release.isPrerelease == (tagBuild != nil) else { return nil }

        let assetURL = release.assets?.first(where: { asset in
            let name = asset.name.lowercased()
            return name.hasSuffix(".dmg") || name.hasSuffix(".zip")
        }).flatMap { URL(string: $0.browserDownloadURL) } ?? releaseURL

        return AppUpdateRelease(version: version, build: tagBuild ?? 0, assetURL: assetURL,
                                releaseURL: releaseURL, isPrerelease: release.isPrerelease)
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: String
        let draft: Bool
        let isPrerelease: Bool
        let assets: [GitHubAsset]?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft
            case isPrerelease = "prerelease"
            case assets
        }
    }

    private struct GitHubAsset: Decodable {
        let name: String
        let browserDownloadURL: String
        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }
}

@MainActor
final class AppUpdateController: ObservableObject {
    enum State: Equatable {
        case unconfigured, idle, checking, noReleasePublished, upToDate
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
    private let currentIsPrerelease: Bool
    private let canInstallAutomatically: () -> Bool
    private var timer: Timer?
    private var operationInProgress = false
    static let checkInterval: TimeInterval = 24 * 60 * 60
    var releasesURL: URL { GitHubReleaseService.releasesURL }

    init(settings: SettingsStore, service: (any AppUpdateService)? = nil,
         currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.1",
         currentBuild: Int = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0,
         currentIsPrerelease: Bool = Bundle.main.infoDictionary?["NIMBARReleaseChannel"] as? String != "stable",
         canInstallAutomatically: @escaping () -> Bool = { false }) {
        self.settings = settings
        self.service = service
        self.currentVersion = currentVersion
        self.currentBuild = currentBuild
        self.currentIsPrerelease = currentIsPrerelease
        self.canInstallAutomatically = canInstallAutomatically
        lastCheckDate = settings.lastUpdateCheckDate
        state = service == nil ? .unconfigured : .idle
    }

    var primaryActionTitle: String {
        switch state {
        case .available: service?.supportsAutomaticInstallation == true
                ? L10n.text("Scarica e installa") : L10n.text("Apri release su GitHub")
        case .readyToInstall: L10n.text("Installa e riavvia")
        case .checking: L10n.text("Verifica in corso…")
        case .downloading: L10n.text("Download in corso…")
        case .installing: L10n.text("Installazione in corso…")
        default: L10n.text("Verifica aggiornamenti")
        }
    }

    var canPerformPrimaryAction: Bool { !operationInProgress }
    var isConfigured: Bool { service != nil }
    var supportsAutomaticInstallation: Bool { service?.supportsAutomaticInstallation == true }
    var isWorking: Bool { operationInProgress }
    var statusTitle: String {
        switch state {
        case .unconfigured: L10n.text("Aggiornamenti non ancora configurati")
        case .idle: L10n.text("Verifica se è disponibile una nuova versione")
        case .checking: L10n.text("Ricerca degli aggiornamenti…")
        case .noReleasePublished: L10n.text("Nessuna release pubblicata")
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
        case .noReleasePublished:
            L10n.text("La repository è collegata, ma non è ancora stata pubblicata alcuna release. Controlla di nuovo più tardi o apri la pagina GitHub.")
        case .available(let release):
            L10n.format("Versione %@ disponibile. Apri la pagina della release per leggere le note e scaricare manualmente il pacchetto.", release.version)
        case .readyToInstall:
            L10n.text("NimBar installerà l’aggiornamento quando le impostazioni saranno chiuse e nessun trascinamento sarà in corso. Puoi anche installarlo adesso.")
        case .failed(let message): message
        case .installed: L10n.text("NimBar verrà riavviata con la nuova versione.")
        default: L10n.format("Versione attuale: %@ beta (build %@).", currentVersion, String(currentBuild))
        }
    }

    func start() {
        // Network access is limited to the public GitHub release API and only
        // when an automatic-check preference is selected.
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
        case .available(let release):
            if service?.supportsAutomaticInstallation == true {
                await download(release, explicitlyInstall: true)
            } else {
                service?.openReleasePage(release)
            }
        case .readyToInstall(let release, let file): await install(release, file: file, explicit: true)
        default: await check()
        }
    }

    func automaticTick(at now: Date = Date()) async {
        guard service != nil, !operationInProgress, settings.updateMode != .manual else { return }
        if settings.updateMode == .installAutomatically, service?.supportsAutomaticInstallation == true {
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
            guard let release else {
                state = .noReleasePublished
                return
            }
            if release.isNewer(than: currentVersion, build: currentBuild, isPrerelease: currentIsPrerelease) {
                state = .available(release)
                if settings.updateMode == .installAutomatically && service.supportsAutomaticInstallation {
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
