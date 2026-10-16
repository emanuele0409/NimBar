// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Darwin
import ScreenCaptureKit

struct MenuBarCandidate: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let bundleIdentifier: String
    let applicationName: String
    let label: String
    let identifier: String?
    let processIdentifier: pid_t
    let index: Int
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    var frame: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    var isSystemOwned: Bool { bundleIdentifier.hasPrefix("com.apple.") }

    var isLiveDivider: Bool {
        identifier == "NimBar.LiveDivider" || label.contains("Trascina un’icona: a sinistra nasconde")
    }

    var isClock: Bool {
        guard isSystemOwned else { return false }
        let description = "\(bundleIdentifier) \(identifier ?? "") \(label)".lowercased()
        return description.contains("clock") || description.contains("orologio")
    }
}

@MainActor
final class MenuBarAccessibility: ObservableObject {
    @Published private(set) var isTrusted = AXIsProcessTrusted()
    @Published private(set) var hasScreenCaptureAccess = CGPreflightScreenCaptureAccess()
    @Published private(set) var needsInputAccess = false
    @Published private(set) var hasInputAccess = CGPreflightListenEventAccess()
    var requiredPermissionsGranted: Bool { isTrusted && hasScreenCaptureAccess && (!needsInputAccess || hasInputAccess) }
    func setLiveEditorAvailability(_ available: Bool) {
        hasInputAccess = CGPreflightListenEventAccess()
        needsInputAccess = !available && !hasInputAccess
    }
    @Published private(set) var items: [MenuBarCandidate] = []
    /// Only elements found in the latest scan of this display. Restored hidden
    /// placeholders are useful in Layout but must never receive native hits.
    private(set) var liveItems: [MenuBarCandidate] = []
    @Published private(set) var capturedIcons: [String: NSImage] = [:]
    @Published private(set) var layoutIconPointSize: CGFloat = 24
    @Published private var status = LocalizedMessage("Autorizzazione Accessibilità necessaria per leggere le icone.")
    var message: String { status.text }
    @Published private(set) var isScanning = false
    @Published private(set) var scannedProcesses = 0
    @Published private(set) var accessibleProcesses = 0
    private var refreshQueued = false
    private var liveRefreshTimer: Timer?
    private var lastCaptureSignature: String?
    private var stableIcons: [String: NSImage] = [:]
    private var savedIconData = UserDefaults.standard.dictionary(forKey: "nativeMenuIconCache.v3") as? [String: Data] ?? [:]
    private var lastCaptureDate = Date.distantPast
    private var imageRefreshCompletions: [() -> Void] = []
    private var refreshCompletions: [() -> Void] = []
    private(set) var displayID = CGMainDisplayID()

    func selectDisplay(containing point: CGPoint) {
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &display, &count) == .success, count == 1 else { return }
        selectDisplay(display)
    }

    func selectDisplay(_ display: CGDirectDisplayID) {
        guard display != displayID else { return }
        displayID = display
        liveItems = []
        lastCaptureSignature = nil
    }

    nonisolated static func candidates(_ candidates: [MenuBarCandidate], on displayBounds: CGRect) -> [MenuBarCandidate] {
        candidates.filter {
            displayBounds.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) &&
            $0.height > 0 && $0.height <= 64 && abs($0.y - displayBounds.minY) <= 12
        }
    }

    private func iconKey(for candidate: MenuBarCandidate) -> String? {
        let siblings = items.filter { $0.bundleIdentifier == candidate.bundleIdentifier }
        if siblings.count == 1 { return candidate.bundleIdentifier }
        guard let identifier = candidate.identifier, !identifier.isEmpty,
              siblings.filter({ $0.identifier == identifier }).count == 1 else { return nil }
        return "\(candidate.bundleIdentifier):\(identifier)"
    }

    func layoutImage(for candidate: MenuBarCandidate) -> NSImage? {
        if let captured = capturedIcons[candidate.id] { return captured }
        guard let key = iconKey(for: candidate) else { return nil }
        if let cached = stableIcons[key] { return cached }
        guard let data = savedIconData[key],
              let image = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSImage.self, from: data) else { return nil }
        stableIcons[key] = image
        return image
    }

    /// The same alpha crop as captured menu symbols, at a bounded resolution.
    /// App icon files often include transparent padding inside their canvas.
    static func normalizedLayoutImage(_ image: NSImage) -> NSImage? {
        let edge = 96
        guard let context = CGContext(data: nil, width: edge, height: edge,
                                      bitsPerComponent: 8, bytesPerRow: edge * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
              let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = CGFloat(edge) / CGFloat(max(source.width, source.height))
        let size = CGSize(width: CGFloat(source.width) * scale, height: CGFloat(source.height) * scale)
        context.draw(source, in: CGRect(x: (CGFloat(edge) - size.width) / 2,
                                       y: (CGFloat(edge) - size.height) / 2,
                                       width: size.width, height: size.height))
        guard let rendered = context.makeImage(),
              let bounds = visibleForegroundBounds(in: rendered),
              let trimmed = rendered.cropping(to: bounds) else { return nil }
        return NSImage(cgImage: trimmed, size: bounds.size)
    }

    func hasUsableLayoutIdentity(_ candidate: MenuBarCandidate) -> Bool {
        func meaningful(_ value: String?) -> Bool {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return false }
            let normalized = value.lowercased()
            guard normalized != candidate.bundleIdentifier.lowercased(),
                  !["item", "unknown", "menu extra", "anonymous", "status item", "menu bar item"].contains(normalized),
                  !normalized.hasPrefix("item-") else { return false }
            return true
        }
        let hasName = meaningful(candidate.label) || (!candidate.isSystemOwned && meaningful(candidate.applicationName))
        return !candidate.isLiveDivider && hasName && layoutImage(for: candidate) != nil
    }

    func refreshPermissionStatus() {
        isTrusted = AXIsProcessTrusted()
        hasScreenCaptureAccess = CGPreflightScreenCaptureAccess()
        hasInputAccess = CGPreflightListenEventAccess()
        if !isTrusted { status = LocalizedMessage("Accessibilità necessaria per gestire le icone della barra dei menu.") }
        else if !hasScreenCaptureAccess { status = LocalizedMessage("Concedi Registrazione schermo per vedere le icone originali.") }
        else { status = LocalizedMessage("Accessibilità e Registrazione schermo autorizzate.") }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openScreenCaptureSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    func refresh(afterCapture: (() -> Void)? = nil, completion: (() -> Void)? = nil) {
        if let afterCapture { imageRefreshCompletions.append(afterCapture) }
        if let completion { refreshCompletions.append(completion) }
        isTrusted = AXIsProcessTrusted()
        guard isTrusted else {
            items = []
            liveItems = []
            capturedIcons = [:]
            status = LocalizedMessage("Accessibilità non autorizzata. NimBar non ha letto né modificato la barra.")
            finishRefreshCallbacks()
            finishImageRefreshCallbacks()
            return
        }
        guard !isScanning else {
            refreshQueued = true
            return
        }
        isScanning = true
        status = LocalizedMessage("Lettura delle voci di menu bar…")
        let display = displayID
        let displayBounds = CGDisplayBounds(display)
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Self.enumerateMenuExtrasWithDiagnostics()
            }.value
            guard display == displayID else {
                isScanning = false
                refreshQueued = false
                refresh()
                return
            }
            let found = Self.candidates(result.items, on: displayBounds)
            liveItems = found
            scannedProcesses = result.scannedProcesses
            accessibleProcesses = result.accessibleProcesses
            let cacheKey = "knownMenuBarCandidates.v2.display.\(display)"
            let savedCandidates = UserDefaults.standard.data(forKey: cacheKey)
                ?? UserDefaults.standard.data(forKey: "knownMenuBarCandidates") ?? Data()
            var knownCandidates = Self.candidates(
                (try? JSONDecoder().decode([MenuBarCandidate].self, from: savedCandidates)) ?? [],
                on: displayBounds)
            if !found.isEmpty {
                var byBundle = Dictionary(knownCandidates.map { ($0.bundleIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
                for candidate in found { byBundle[candidate.bundleIdentifier] = candidate }
                knownCandidates = Array(byBundle.values)
                if let data = try? JSONEncoder().encode(knownCandidates) {
                    UserDefaults.standard.set(data, forKey: cacheKey)
                }
            }
            let currentBundles = Set(found.map(\.bundleIdentifier))
            let assignedBundles = Set((UserDefaults.standard.stringArray(forKey: "nativeHiddenBundleIDs") ?? [])
                + (UserDefaults.standard.stringArray(forKey: "nativeAlwaysHiddenBundleIDs") ?? []))
            let restoredHidden = knownCandidates.filter {
                assignedBundles.contains($0.bundleIdentifier) && !currentBundles.contains($0.bundleIdentifier)
            }
            let updatedItems = (found + restoredHidden).sorted { lhs, rhs in
                if lhs.x != rhs.x { return lhs.x < rhs.x }
                return lhs.applicationName.localizedStandardCompare(rhs.applicationName) == .orderedAscending
            }
            if updatedItems != items { items = updatedItems }
            // Drag decisions need current owner frames, not the much slower
            // screenshot capture. Callbacks queued by callbacks run next scan.
            finishRefreshCallbacks()
            let signature = Self.captureSignature(found)
            if signature != lastCaptureSignature || Date().timeIntervalSince(lastCaptureDate) >= 2 {
                var snapshots = await Task.detached(priority: .utility) {
                    Self.captureMenuBarIcons(found)
                }.value
                if snapshots.count < found.filter({ !$0.isLiveDivider }).count {
                    let onscreen = await Self.captureDisplayMenuIcons(found, display: display)
                    snapshots.merge(onscreen) { native, _ in native }
                }
                let sharp = await Self.captureRetinaMenuIcons(for: found, from: result.items, selectedDisplay: display)
                snapshots.merge(sharp) { _, retina in retina }
                if display == displayID {
                    // Keep the last valid symbol while an item is hidden or moving.
                    // A geometric ID change must never swap in an application icon.
                    for candidate in found {
                        guard var image = snapshots[candidate.id] else { continue }
                        if let retained = layoutImage(for: candidate), Self.pixelScale(retained) > Self.pixelScale(image) {
                            image = retained
                        }
                        capturedIcons[candidate.id] = image
                        if let key = iconKey(for: candidate) {
                            stableIcons[key] = image
                            if let data = try? NSKeyedArchiver.archivedData(withRootObject: image, requiringSecureCoding: true) {
                                savedIconData[key] = data
                            }
                        }
                    }
                    capturedIcons = capturedIcons.filter { key, _ in items.contains { $0.id == key } }
                    UserDefaults.standard.set(savedIconData, forKey: "nativeMenuIconCache.v3")
                    lastCaptureSignature = signature
                    lastCaptureDate = Date()
                }
            }
            finishImageRefreshCallbacks()
            isTrusted = AXIsProcessTrusted()
            hasScreenCaptureAccess = CGPreflightScreenCaptureAccess()
            status = items.isEmpty
                ? LocalizedMessage("macOS non ha esposto icone accessibili. Processi in esecuzione: %@; gruppi letti: %@. Verifica Accessibilità.", [.number(scannedProcesses), .number(accessibleProcesses)])
                : LocalizedMessage("Trovate %@ icone nella barra macOS.", [.number(items.count)])
            isScanning = false
            if refreshQueued {
                refreshQueued = false
                refresh()
            }
        }
    }

    private func finishImageRefreshCallbacks() {
        let completions = imageRefreshCompletions
        imageRefreshCompletions.removeAll()
        completions.forEach { $0() }
    }

    private func finishRefreshCallbacks() {
        let completions = refreshCompletions
        refreshCompletions.removeAll()
        completions.forEach { $0() }
    }

    func startLiveUpdates() {
        guard liveRefreshTimer == nil else { return }
        // Layout is intentionally pinned to the primary display. Live editing
        // uses a separate scanner owned by AppDelegate for the active screen.
        refresh()
        liveRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func stopLiveUpdates() {
        liveRefreshTimer?.invalidate()
        liveRefreshTimer = nil
    }

    private nonisolated static func captureSignature(_ items: [MenuBarCandidate]) -> String {
        items.sorted { $0.id < $1.id }.map {
            "\($0.id):\($0.x),\($0.y),\($0.width),\($0.height)"
        }.joined(separator: "|")
    }

    private nonisolated static func captureMenuBarIcons(_ items: [MenuBarCandidate]) -> [String: NSImage] {
        guard CGPreflightScreenCaptureAccess(), !items.isEmpty else { return [:] }
        let windows = MenuBarNativeHider.menuBarWindows().filter { ($0["container"] as? NSNumber)?.boolValue != true }
        var result: [String: NSImage] = [:]
        var surfaces: [UInt32: CGImage] = [:]
        for item in items where !item.isLiveDivider {
            let exact = windows.filter { window in
                guard let frame = window["frame"] as? NSValue else { return false }
                return captureFramesMatch(item.frame, frame.rectValue)
            }
            // macOS 27 can host all status items in one MenuBarAgent window.
            // Capture that native surface once, then use AX frames from the
            // same display; never sample the desktop behind it.
            let containers = windows.filter { window in
                guard (window["container"] as? NSNumber)?.boolValue == true,
                      let frame = (window["frame"] as? NSValue)?.rectValue else { return false }
                return frame.height <= 64 && frame.contains(item.frame)
            }
            let matches = exact.isEmpty ? containers : exact
            guard matches.count == 1, let window = matches.first,
                  let number = window["windowID"] as? NSNumber,
                  let frame = (window["frame"] as? NSValue)?.rectValue else { continue }
            let id = number.uint32Value
            if surfaces[id] == nil,
               let captured = MenuBarNativeHider.captureMenuBarWindow(id),
               let raw = captured.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                surfaces[id] = rgbaImage(raw)
            }
            guard let surface = surfaces[id] else { continue }
            let scaleX = CGFloat(surface.width) / frame.width
            let scaleY = CGFloat(surface.height) / frame.height
            let crop = CGRect(x: (item.x - frame.minX) * scaleX, y: (item.y - frame.minY) * scaleY,
                              width: item.width * scaleX, height: item.height * scaleY).integral
            guard let source = surface.cropping(to: crop),
                  let foreground = visibleForegroundBounds(in: source),
                  let trimmed = source.cropping(to: foreground) else { continue }
            let current = MenuBarNativeHider.menuBarWindows().first {
                ($0["windowID"] as? NSNumber)?.uint32Value == id
            }
            guard let currentFrame = (current?["frame"] as? NSValue)?.rectValue,
                  captureFramesMatch(frame, currentFrame) else { continue }
            let image = NSImage(cgImage: trimmed, size: NSSize(width: CGFloat(trimmed.width) / scaleX,
                                                               height: CGFloat(trimmed.height) / scaleY))
            image.isTemplate = isMonochrome(trimmed)
            result[item.id] = image
        }
        return result
    }

    private static func pixelScale(_ image: NSImage) -> CGFloat {
        guard let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 0 }
        return CGFloat(bitmap.height) / max(image.size.height, 1)
    }

    /// Geometry stays on the display being edited. The settings preview can
    /// use the same uniquely identified menu symbol on a Retina replica, so a
    /// 1x external screen never downgrades a 2x preview on the built-in display.
    private static func captureRetinaMenuIcons(for targets: [MenuBarCandidate], from all: [MenuBarCandidate],
                                              selectedDisplay: CGDirectDisplayID) async -> [String: NSImage] {
        let screens = NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, CGFloat)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (number.uint32Value, screen.backingScaleFactor)
        }
        guard let best = screens.max(by: { $0.1 < $1.1 }), best.1 >= 2, best.0 != selectedDisplay else { return [:] }
        let sources = Self.candidates(all, on: CGDisplayBounds(best.0))
        let images = await captureDisplayMenuIcons(sources, display: best.0)
        var result: [String: NSImage] = [:]
        for target in targets {
            let owners = sources.filter { $0.bundleIdentifier == target.bundleIdentifier && $0.processIdentifier == target.processIdentifier }
            let exact = owners.filter { target.identifier != nil && $0.identifier == target.identifier }
            let matches = exact.isEmpty && !target.isSystemOwned ? owners : exact
            guard matches.count == 1, let source = matches.first, let image = images[source.id], pixelScale(image) >= 2 else { continue }
            result[target.id] = image
        }
        return result
    }

    /// macOS 27's MenuBarAgent can composite the items outside the legacy
    /// CGS menu window. Capture a coherent, explicitly scaled strip of only
    /// those native surfaces. Keep their pixels and alpha, without backdrop
    /// subtraction, app icons or system-symbol substitutions.
    private static func captureDisplayMenuIcons(_ items: [MenuBarCandidate], display: CGDirectDisplayID) async -> [String: NSImage] {
        guard CGPreflightScreenCaptureAccess(), !items.isEmpty,
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let screen = content.displays.first(where: { $0.displayID == display }) else { return [:] }
        let bounds = CGDisplayBounds(display)
        let candidates = items.filter { !$0.isLiveDivider && bounds.contains($0.frame) }
        guard !candidates.isEmpty else { return [:] }
        let height = min(64, candidates.map { $0.frame.maxY - bounds.minY }.max() ?? 0)
        guard height > 0 else { return [:] }
        let nativeIDs = Set(MenuBarNativeHider.menuBarWindows().compactMap { ($0["windowID"] as? NSNumber)?.uint32Value })
        let menuWindows = content.windows.filter { nativeIDs.contains($0.windowID) }
        guard !menuWindows.isEmpty else { return [:] }
        let filter = SCContentFilter(display: screen, including: menuWindows)
        let configuration = SCStreamConfiguration()
        let scale = max(2, CGFloat(filter.pointPixelScale))
        configuration.sourceRect = CGRect(x: 0, y: 0, width: bounds.width, height: height)
        configuration.width = Int((bounds.width * scale).rounded())
        configuration.height = Int((height * scale).rounded())
        configuration.showsCursor = false
        configuration.captureResolution = .best
        configuration.ignoreShadowsDisplay = true
        guard let screenshot = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) else { return [:] }
        let current = await Task.detached { Self.enumerateMenuExtras() }.value
        let scaleX = CGFloat(screenshot.width) / bounds.width
        let scaleY = CGFloat(screenshot.height) / height
        var images: [String: NSImage] = [:]
        for item in candidates {
            guard current.contains(where: { $0.processIdentifier == item.processIdentifier && $0.id == item.id && Self.captureFramesMatch($0.frame, item.frame) }) else { continue }
            let rect = CGRect(x: (item.x - bounds.minX) * scaleX,
                              y: (item.y - bounds.minY) * scaleY,
                              width: item.width * scaleX, height: item.height * scaleY).integral
            guard let crop = screenshot.cropping(to: rect),
                  let rgba = Self.rgbaImage(crop),
                  let clean = Self.cleanMenuSurface(rgba),
                  Self.visibleForegroundBounds(in: clean) != nil else { continue }
            // Preserve the native canvas and pixel origin: re-centring a tight
            // crop can shift odd-width Retina glyphs by half a physical pixel.
            let image = NSImage(cgImage: clean, size: NSSize(width: item.width, height: item.height))
            image.isTemplate = Self.isMonochrome(clean)
            images[item.id] = image
        }
        return images
    }

    private nonisolated static func rgbaImage(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    /// SCK represents empty pixels in a composited menu surface with alpha
    /// 1/255. Remove only that compositor sentinel, not estimated background
    /// colours. Normalise inactive menu opacity without resampling the pixels.
    private nonisolated static func cleanMenuSurface(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let count = image.width * image.height
        var maximum = 0
        for index in 0..<count { maximum = max(maximum, Int(bytes[index * 4 + 3])) }
        guard maximum > 8 else { return nil }
        for index in 0..<count {
            let offset = index * 4
            let alpha = Int(bytes[offset + 3])
            if alpha <= 2 {
                for channel in 0..<4 { bytes[offset + channel] = 0 }
            } else {
                for channel in 0..<4 {
                    bytes[offset + channel] = UInt8(min(255, Int(bytes[offset + channel]) * 255 / maximum))
                }
            }
        }
        return context.makeImage()
    }

    private nonisolated static func captureFramesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 2 && abs(lhs.minY - rhs.minY) <= 2 &&
        abs(lhs.width - rhs.width) <= 2 && abs(lhs.height - rhs.height) <= 2
    }

    private nonisolated static func isMonochrome(_ image: CGImage) -> Bool {
        guard image.bitsPerPixel == 32, let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return false }
        var opaque = 0
        var colored = 0
        for y in 0..<image.height {
            for x in 0..<image.width {
                let offset = y * image.bytesPerRow + x * 4
                guard bytes[offset + 3] > 8 else { continue }
                opaque += 1
                let channels = [Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2])]
                if (channels.max()! - channels.min()!) * 255 / Int(bytes[offset + 3]) > 35 { colored += 1 }
            }
        }
        return opaque > 0 && Double(colored) / Double(opaque) < 0.20
    }

    private nonisolated static func visibleForegroundBounds(in image: CGImage) -> CGRect? {
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data),
              image.bitsPerPixel == 32 else { return nil }
        var minX = image.width
        var minY = image.height
        var maxX = -1
        var maxY = -1
        var visiblePixels = 0
        for y in 0..<image.height {
            for x in 0..<image.width {
                if bytes[y * image.bytesPerRow + x * 4 + 3] > 8 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                    visiblePixels += 1
                }
            }
        }
        guard maxX >= minX, maxY >= minY,
              maxX - minX >= 2, maxY - minY >= 2,
              Double(visiblePixels) / Double(image.width * image.height) >= 0.015 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    nonisolated static func enumerateMenuExtras() -> [MenuBarCandidate] {
        enumerateMenuExtrasWithDiagnostics().items
    }

    nonisolated static func applicationMenuBarFrames(processIdentifier: pid_t) -> [CGRect] {
        let application = AXUIElementCreateApplication(processIdentifier)
        guard let rawMenuBar = Self.attribute(kAXMenuBarAttribute as CFString, from: application) else { return [] }
        let menuBar = unsafeBitCast(rawMenuBar, to: AXUIElement.self)
        return Self.children(of: menuBar).compactMap { item in
            guard Self.attribute(kAXRoleAttribute as CFString, from: item) as? String == kAXMenuBarItemRole as String else { return nil }
            return Self.frame(of: item)
        }
    }

    nonisolated static func enumerateMenuExtrasWithDiagnostics() -> (items: [MenuBarCandidate], scannedProcesses: Int, accessibleProcesses: Int) {
        let apps = NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated && $0.processIdentifier != getpid()
        }
        let agents = apps.filter {
            ["com.apple.MenuBarAgent", "com.apple.controlcenter", "com.apple.systemuiserver"].contains($0.bundleIdentifier ?? "")
        }
        guard !agents.isEmpty else {
            return ([], apps.count, 0)
        }
        var result: [MenuBarCandidate] = []
        var groupCount = 0
        var seen = Set<String>()

        for agent in agents {
            let root = AXUIElementCreateApplication(agent.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.3)
            for (windowIndex, window) in Self.children(of: root).enumerated() {
                guard Self.attribute(kAXRoleAttribute as CFString, from: window) as? String == kAXWindowRole as String else { continue }
                for (groupIndex, group) in Self.children(of: window).enumerated() {
                    guard let frame = Self.frame(of: group), frame.width > 0, frame.height > 0 else { continue }
                    groupCount += 1
                    var ownerPIDs = Set<pid_t>()
                    var titles: [String] = []
                    var identifiers: [String] = []
                    var remainingNodes = 384
                    Self.describe(group, agentPID: agent.processIdentifier, depth: 0,
                                  remainingNodes: &remainingNodes,
                                  owners: &ownerPIDs, titles: &titles, identifiers: &identifiers)
                    let owners = ownerPIDs.compactMap { pid in
                        NSRunningApplication(processIdentifier: pid).flatMap { app -> (NSRunningApplication, String)? in
                            guard let bundle = app.bundleIdentifier, !bundle.isEmpty else { return nil }
                            return (app, bundle)
                        }
                    }
                    let ownerBundleIDs = Set(owners.map(\.1))
                    guard ownerBundleIDs.count <= 1 else { continue }
                    let ownerApp: NSRunningApplication
                    let bundleID: String
                    if let owner = owners.first {
                        (ownerApp, bundleID) = owner
                    } else if ownerPIDs.isEmpty, let agentBundleID = agent.bundleIdentifier {
                        // System menu extras may be owned by the menu agent itself;
                        // retain the real AX frame and screenshot, and keep them immovable.
                        ownerApp = agent
                        bundleID = agentBundleID
                    } else {
                        continue
                    }
                    let cleanTitles = titles.filter { !$0.isEmpty }
                    let cleanIdentifiers = identifiers.filter { !$0.isEmpty }
                    let label = cleanTitles.first ?? cleanIdentifiers.first ?? ""
                    let stable = cleanIdentifiers.first ?? cleanTitles.first ?? "anonymous"
                    let normalizedX = Int((frame.midX / 8).rounded())
                    let normalizedY = Int((frame.midY / 8).rounded())
                    let uniqueness = "\(bundleID):\(normalizedX):\(normalizedY)"
                    guard seen.insert(uniqueness).inserted else { continue }
                    let isGeometricDuplicate = result.contains { existing in
                        guard existing.bundleIdentifier == bundleID else { return false }
                        let tolerance = max(8, min(existing.width, frame.width) * 0.55)
                        return abs(existing.frame.midX - frame.midX) < tolerance
                            && abs(existing.frame.midY - frame.midY) < 8
                    }
                    guard !isGeometricDuplicate else { continue }
                    let index = windowIndex * 10_000 + groupIndex
                    let candidate = MenuBarCandidate(
                        id: "\(bundleID):\(stable):\(normalizedX):\(normalizedY)", bundleIdentifier: bundleID,
                        applicationName: ownerApp.localizedName ?? bundleID, label: label,
                        identifier: cleanIdentifiers.first, processIdentifier: ownerApp.processIdentifier,
                        index: index, x: frame.origin.x, y: frame.origin.y,
                        width: frame.width, height: frame.height
                    )
                    result.append(candidate)
                }
            }
        }
        // Do not drop an AX item because another item's Window Server frame
        // happened to match. Each image is matched independently at capture time.
        let discovered = result
        return (discovered.sorted { $0.x < $1.x }, apps.count, groupCount)
    }

    private nonisolated static func children(of element: AXUIElement) -> [AXUIElement] {
        AXUIElementSetMessagingTimeout(element, 0.2)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &raw) == .success,
              let raw, let children = raw as? [AXUIElement] else { return [] }
        return children
    }

    private nonisolated static func attribute(_ name: CFString, from element: AXUIElement) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, 0.2)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
        return value
    }

    private nonisolated static func frame(of element: AXUIElement) -> CGRect? {
        var raw = Self.attribute("AXFrame" as CFString, from: element)
        if let raw, CFGetTypeID(raw) == AXValueGetTypeID() {
            var frame = CGRect.zero
            if AXValueGetValue(unsafeBitCast(raw, to: AXValue.self), .cgRect, &frame) { return frame }
        }
        raw = Self.attribute(kAXPositionAttribute as CFString, from: element)
        let position = Self.point(from: raw)
        raw = Self.attribute(kAXSizeAttribute as CFString, from: element)
        guard let position, let size = Self.size(from: raw) else { return nil }
        return CGRect(origin: position, size: size)
    }

    private nonisolated static func describe(_ element: AXUIElement, agentPID: pid_t, depth: Int,
                                            remainingNodes: inout Int,
                                            owners: inout Set<pid_t>, titles: inout [String],
                                            identifiers: inout [String]) {
        guard depth <= 4, remainingNodes > 0 else { return }
        remainingNodes -= 1
        var pid: pid_t = 0
        _ = AXUIElementGetPid(element, &pid)
        if pid != agentPID && pid != 0 { owners.insert(pid) }
        for key in [kAXTitleAttribute, kAXDescriptionAttribute] {
            if let text = Self.attribute(key as CFString, from: element) as? String, !text.isEmpty, !titles.contains(text) {
                titles.append(text)
            }
        }
        if let identifier = Self.attribute(kAXIdentifierAttribute as CFString, from: element) as? String,
           !identifier.isEmpty, !identifiers.contains(identifier) {
            identifiers.append(identifier)
        }
        if Self.attribute(kAXRoleAttribute as CFString, from: element) as? String == kAXApplicationRole as String { return }
        for child in Self.children(of: element) {
            Self.describe(child, agentPID: agentPID, depth: depth + 1,
                          remainingNodes: &remainingNodes,
                          owners: &owners, titles: &titles, identifiers: &identifiers)
        }
    }

    private nonisolated static func framesMatch(_ accessibilityFrame: CGRect, _ windowFrame: CGRect) -> Bool {
        abs(accessibilityFrame.minX - windowFrame.minX) <= 8 &&
        abs(accessibilityFrame.minY - windowFrame.minY) <= 5 &&
        abs(accessibilityFrame.width - windowFrame.width) <= 10 &&
        abs(accessibilityFrame.height - windowFrame.height) <= 8
    }

    private nonisolated static func point(from raw: CFTypeRef?) -> CGPoint? {
        guard let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(unsafeBitCast(raw, to: AXValue.self), .cgPoint, &point) else { return nil }
        return point
    }

    private nonisolated static func size(from raw: CFTypeRef?) -> CGSize? {
        guard let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(raw, to: AXValue.self), .cgSize, &size) else { return nil }
        return size
    }
}
