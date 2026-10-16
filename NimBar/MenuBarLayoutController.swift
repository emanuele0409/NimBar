// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import Combine

enum MenuBarLayoutZone: String {
    case visible, hidden, alwaysHidden
}

/// A drag owns an immutable source snapshot. Its result uses the *current*
/// divider and resolves the source owner again after macOS reorders windows.
struct LiveDividerDragSession {
    struct Drop {
        let candidate: MenuBarCandidate
        let zone: MenuBarLayoutZone
    }

    let start: CGPoint
    private let originalDivider: CGRect
    private let sources: [MenuBarCandidate]
    private let isDividerDrag: Bool
    private let displayBounds: CGRect?

    init?(start: CGPoint, divider: CGRect, candidates: [MenuBarCandidate], alwaysHidden: Set<String>, ownPID: pid_t,
          displayBounds: CGRect? = nil) {
        guard !divider.isEmpty, start.y >= divider.minY - 8, start.y <= divider.maxY + 8 else { return nil }
        let eligible = candidates.filter {
            !$0.isSystemOwned && $0.processIdentifier != ownPID && !alwaysHidden.contains($0.bundleIdentifier)
        }
        self.start = start
        self.displayBounds = displayBounds
        originalDivider = divider
        isDividerDrag = divider.contains(start)
        if isDividerDrag {
            sources = eligible.filter { Self.resolve($0, in: candidates) != nil }
        } else {
            let matches = eligible.filter { $0.frame.contains(start) }
            guard matches.count == 1, Self.resolve(matches[0], in: candidates) != nil else { return nil }
            sources = matches
        }
    }

    static func resolve(_ source: MenuBarCandidate, in candidates: [MenuBarCandidate]) -> MenuBarCandidate? {
        let matches = candidates.filter { $0.bundleIdentifier == source.bundleIdentifier }
        guard matches.count == 1, let match = matches.first,
              match.processIdentifier == source.processIdentifier else { return nil }
        return match
    }

    func drops(at release: CGPoint, divider: CGRect, candidates: [MenuBarCandidate]) -> [Drop] {
        guard !divider.isEmpty, hypot(release.x - start.x, release.y - start.y) > 7,
              displayBounds?.contains(release) != false,
              release.y >= divider.minY - 8, release.y <= divider.maxY + 8 else { return [] }
        return sources.compactMap { source in
            guard let current = Self.resolve(source, in: candidates) else { return nil }
            let left: Bool
            if isDividerDrag {
                left = current.frame.midX < divider.midX
                guard (source.frame.midX < originalDivider.midX) != left else { return nil }
            } else {
                // Use the user's drop point, including when macOS snaps an icon
                // back before the visibility assertion is applied.
                guard abs(release.x - divider.midX) > 2 else { return nil }
                left = release.x < divider.midX
            }
            return Drop(candidate: current, zone: left ? .hidden : .visible)
        }
    }
}

@MainActor
final class MenuBarLayoutController: ObservableObject {
    @Published private(set) var isConfigured = UserDefaults.standard.bool(forKey: "layoutConfigured")
    @Published private(set) var isCollapsed = false {
        didSet { if oldValue != isCollapsed { onCollapsedChanged?(isCollapsed) } }
    }
    @Published private(set) var isMovingItem = false
    @Published private(set) var isEditingLiveDivider = false
    @Published private var status = LocalizedMessage("Configura il Layout per iniziare.")
    var message: String { status.text }
    @Published private(set) var hiddenBundleIDs = Set(UserDefaults.standard.stringArray(forKey: "nativeHiddenBundleIDs") ?? [])
    @Published private(set) var alwaysHiddenBundleIDs = Set(UserDefaults.standard.stringArray(forKey: "nativeAlwaysHiddenBundleIDs") ?? [])

    private let hider = MenuBarNativeHider()
    private var moveGeneration = 0
    private var liveHiddenOverrides: Set<String> = []
    private var visibilityRevision = 0
    private var visibilityInFlight = false
    private var pendingVisibility: (() -> Void)?
    var onCollapsedChanged: ((Bool) -> Void)?
    var onVisibilityApplied: (() -> Void)?

    func refreshVisibility() { onCollapsedChanged?(isCollapsed) }

    var isNativeBackendAvailable: Bool { hider.isAvailable }

    func initializeHiddenSection() {
        isConfigured = true
        UserDefaults.standard.set(true, forKey: "layoutConfigured")
        if let bundle = Bundle.main.bundleIdentifier {
            hiddenBundleIDs.remove(bundle)
            alwaysHiddenBundleIDs.remove(bundle)
            saveAssignments()
        }
        status = hider.isAvailable
            ? LocalizedMessage("Layout pronto. Trascina le icone tra le sezioni; le modifiche si applicano subito.")
            : LocalizedMessage("Layout visivo pronto, ma questa versione di macOS non espone il servizio nativo per nascondere le icone.")
    }

    func resumeSavedAssignments() {
        guard isConfigured else { return }
        isCollapsed = true
        applyVisibility()
    }

    func toggleHiddenSection() {
        guard isConfigured else {
            status = LocalizedMessage("Configura prima il Layout nelle impostazioni.")
            return
        }
        guard !hiddenBundleIDs.isEmpty || !alwaysHiddenBundleIDs.isEmpty else {
            status = LocalizedMessage("Sposta almeno un’icona nella sezione Nascoste.")
            return
        }
        isCollapsed.toggle()
        applyVisibility()
    }

    var hasHiddenItems: Bool { !hiddenBundleIDs.isEmpty || !alwaysHiddenBundleIDs.isEmpty }

    func beginLiveDividerEditing() {
        guard !isEditingLiveDivider else { return }
        liveHiddenOverrides = []
        isEditingLiveDivider = true
        applyVisibility()
    }

    func endLiveDividerEditing() {
        guard isEditingLiveDivider else { return }
        isEditingLiveDivider = false
        liveHiddenOverrides = []
        applyVisibility()
    }

    func applyLiveVisibility(_ source: MenuBarCandidate, to zone: MenuBarLayoutZone,
                             sourceSnapshot: [MenuBarCandidate]) {
        guard isEditingLiveDivider, zone != .alwaysHidden, !source.isSystemOwned,
              source.processIdentifier != getpid(), !isAlwaysHidden(source),
              LiveDividerDragSession.resolve(source, in: sourceSnapshot) != nil,
              NSRunningApplication(processIdentifier: source.processIdentifier)?.bundleIdentifier == source.bundleIdentifier else { return }
        let bundle = source.bundleIdentifier
        let wasHidden = hiddenBundleIDs.contains(bundle)
        let shouldHide = zone == .hidden
        guard wasHidden != shouldHide || liveHiddenOverrides.contains(bundle) != shouldHide else { return }
        if shouldHide {
            hiddenBundleIDs.insert(bundle)
            liveHiddenOverrides.insert(bundle)
            isCollapsed = true
        } else {
            hiddenBundleIDs.remove(bundle)
            liveHiddenOverrides.remove(bundle)
            if !hasHiddenItems { isCollapsed = false }
        }
        moveGeneration += 1
        saveAssignments()
        applyVisibility()
    }

    func isAlwaysHidden(_ candidate: MenuBarCandidate) -> Bool {
        alwaysHiddenBundleIDs.contains(candidate.bundleIdentifier)
    }

    func isHidden(_ candidate: MenuBarCandidate) -> Bool {
        hiddenBundleIDs.contains(candidate.bundleIdentifier) || alwaysHiddenBundleIDs.contains(candidate.bundleIdentifier)
    }

    func move(_ candidate: MenuBarCandidate, toHidden: Bool, access: MenuBarAccessibility) {
        move(candidate, to: toHidden ? .hidden : .visible, access: access)
    }

    func move(_ candidate: MenuBarCandidate, to zone: MenuBarLayoutZone, access: MenuBarAccessibility) {
        guard isConfigured else {
            status = LocalizedMessage("Configura prima il Layout nelle impostazioni.")
            return
        }
        guard access.isTrusted else {
            status = LocalizedMessage("Concedi prima il permesso Accessibilità.")
            return
        }
        guard !candidate.isSystemOwned, candidate.processIdentifier != getpid() else {
            status = LocalizedMessage("macOS gestisce direttamente questa icona di sistema.")
            return
        }
        guard candidate.bundleIdentifier != Bundle.main.bundleIdentifier else {
            status = LocalizedMessage("L’icona di NimBar resta sempre visibile per poter riaprire le app nascoste e le impostazioni.")
            return
        }
        guard let currentCandidate = LiveDividerDragSession.resolve(candidate, in: access.items) else {
            status = LocalizedMessage("Questa app ha più icone nella barra. Per evitare di nasconderle tutte, il trascinamento non ha modificato nulla.")
            return
        }
        // IDs include screen coordinates and legitimately change on a native
        // reorder. Resolve the same unique owner again instead of rejecting it.
        let candidate = currentCandidate
        isEditingLiveDivider = false
        liveHiddenOverrides = []
        let bundle = candidate.bundleIdentifier
        let previousHidden = hiddenBundleIDs
        let previousAlwaysHidden = alwaysHiddenBundleIDs
        let previousCollapsed = isCollapsed
        switch zone {
        case .visible:
            hiddenBundleIDs.remove(bundle)
            alwaysHiddenBundleIDs.remove(bundle)
        case .hidden:
            hiddenBundleIDs.insert(bundle)
            alwaysHiddenBundleIDs.remove(bundle)
        case .alwaysHidden:
            hiddenBundleIDs.remove(bundle)
            alwaysHiddenBundleIDs.insert(bundle)
        }
        if hiddenBundleIDs.isEmpty && alwaysHiddenBundleIDs.isEmpty {
            isCollapsed = false
        }
        saveAssignments()
        if zone != .visible { isCollapsed = true }
        isMovingItem = true
        status = LocalizedMessage("Applico subito la sezione a %@…", [.text(candidate.applicationName)])
        moveGeneration += 1
        let generation = moveGeneration
        let bundlesToHide = Self.bundlesToHide(hidden: hiddenBundleIDs,
                                               alwaysHidden: alwaysHiddenBundleIDs,
                                               isCollapsed: isCollapsed && !isEditingLiveDivider)
        applyVisibility(verification: (bundlesToHide, zone == .visible ? bundle : nil),
                        rollback: (previousHidden, previousAlwaysHidden, previousCollapsed), generation: generation)
    }

    func isBeyondMainDivider(_ candidate: MenuBarCandidate) -> Bool {
        isHidden(candidate)
    }

    /// Shared visibility rule for both the Layout editor and the live divider.
    /// Expanding the hidden section temporarily reveals `.hidden` apps while
    /// preserving the `.alwaysHidden` set.
    nonisolated static func bundlesToHide(hidden: Set<String>, alwaysHidden: Set<String>, isCollapsed: Bool) -> Set<String> {
        alwaysHidden.union(isCollapsed ? hidden : [])
    }

    func showAllManagedItems(using access: MenuBarAccessibility) {
        guard access.isTrusted else {
            status = LocalizedMessage("Concedi prima il permesso Accessibilità.")
            return
        }
        isCollapsed = false
        applyVisibility()
        if alwaysHiddenBundleIDs.isEmpty {
            status = LocalizedMessage("Tutte le icone sono visibili temporaneamente.")
        } else {
            status = LocalizedMessage("Icone nascoste mostrate temporaneamente; le icone Sempre nascoste restano nascoste.")
        }
    }

    private func saveAssignments() {
        UserDefaults.standard.set(Array(hiddenBundleIDs), forKey: "nativeHiddenBundleIDs")
        UserDefaults.standard.set(Array(alwaysHiddenBundleIDs), forKey: "nativeAlwaysHiddenBundleIDs")
    }

    private func applyVisibility(verification: (hiddenBundles: Set<String>, visibleBundle: String?)? = nil,
                                 rollback: (Set<String>, Set<String>, Bool)? = nil,
                                 generation: Int? = nil) {
        visibilityRevision += 1
        let revision = visibilityRevision
        if visibilityInFlight {
            pendingVisibility = { [weak self] in
                self?.performVisibility(revision: revision, verification: verification, rollback: rollback, generation: generation)
            }
            return
        }
        performVisibility(revision: revision, verification: verification, rollback: rollback, generation: generation)
    }

    private func performVisibility(revision: Int,
                                   verification: (hiddenBundles: Set<String>, visibleBundle: String?)?,
                                   rollback: (Set<String>, Set<String>, Bool)?, generation: Int?) {
        let bundlesToHide = isEditingLiveDivider ? alwaysHiddenBundleIDs.union(liveHiddenOverrides)
            : Self.bundlesToHide(hidden: hiddenBundleIDs,
                                               alwaysHidden: alwaysHiddenBundleIDs,
                                               isCollapsed: isCollapsed)
        if bundlesToHide.isEmpty {
            hider.restoreAll()
            isMovingItem = false
            status = LocalizedMessage("Tutte le icone sono visibili.")
            onVisibilityApplied?()
            return
        }
        isMovingItem = true
        visibilityInFlight = true
        hider.applyHiddenBundleIdentifiers(bundlesToHide) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.visibilityInFlight = false
                if revision != self.visibilityRevision {
                    let pending = self.pendingVisibility
                    self.pendingVisibility = nil
                    pending?()
                    return
                }
                if let error {
                    self.isMovingItem = false
                    self.restoreAssignments(rollback)
                    self.status = LocalizedMessage("macOS non ha applicato il nascondimento: %@", [.error(error as NSError)])
                    if let rollback {
                        _ = rollback
                        self.applyVisibility()
                    }
                    self.onVisibilityApplied?()
                } else {
                    self.onVisibilityApplied?()
                    guard let verification else {
                        self.isMovingItem = false
                        self.status = self.isCollapsed ? LocalizedMessage("Sezione Nascoste chiusa.") : LocalizedMessage("Layout applicato subito alla barra dei menu.")
                        return
                    }
                    self.isMovingItem = false
                    self.status = LocalizedMessage("Richiesta accettata; controllo la barra macOS…")
                    self.verifyVisibility(verification, generation: generation ?? self.moveGeneration, attempt: 0)
                }
            }
        }
    }

    private func verifyVisibility(_ verification: (hiddenBundles: Set<String>, visibleBundle: String?),
                                  generation: Int, attempt: Int) {
        // MenuBarAgent may update its accessibility tree after the assertion has
        // already taken effect. Poll briefly; never tear down an accepted assertion
        // just because AX is stale for one snapshot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, generation == self.moveGeneration else { return }
                let visibleBundles = await Task.detached(priority: .userInitiated) {
                    Set(MenuBarAccessibility.enumerateMenuExtras().map(\.bundleIdentifier))
                }.value
                guard generation == self.moveGeneration else { return }
                let hiddenAreAbsent = verification.hiddenBundles.isDisjoint(with: visibleBundles)
                let expectedVisibleIsPresent = verification.visibleBundle.map { visibleBundles.contains($0) } ?? true
                if hiddenAreAbsent && expectedVisibleIsPresent {
                    self.status = verification.visibleBundle == nil
                        ? LocalizedMessage("Icona nascosta nella barra macOS.")
                        : LocalizedMessage("Icona ripristinata nella barra macOS.")
                } else if attempt < 5 {
                    self.verifyVisibility(verification, generation: generation, attempt: attempt + 1)
                } else {
                    // Keep the native assertion and the user's assignment in place:
                    // rolling them back here caused a successful drag to appear lost.
                    self.status = LocalizedMessage("Richiesta inviata a macOS, ma MenuBarAgent mostra ancora %@ voci. L’assegnazione resta attiva; riprova tra qualche secondo.", [.number(visibleBundles.count)])
                }
            }
        }
    }

    private func restoreAssignments(_ state: (Set<String>, Set<String>, Bool)?) {
        guard let state else { return }
        hiddenBundleIDs = state.0
        alwaysHiddenBundleIDs = state.1
        isCollapsed = state.2
        saveAssignments()
    }
}
