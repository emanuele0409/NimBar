// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import SwiftUI
import QuartzCore

/// A gesture owns one real display snapshot until mouseUp. Cached Layout
/// placeholders and a later pointer/display switch cannot change its source.
struct LiveIconDragSession {
    let source: MenuBarCandidate
    let displayID: CGDirectDisplayID
    let displayBounds: CGRect
    let menuBarBounds: CGRect
    var dividerX: CGFloat
    let initialDividerX: CGFloat
    let minimumDividerX: CGFloat
    let maximumDividerX: CGFloat
    let start: CGPoint
    let generation: Int

    init?(source: MenuBarCandidate, candidates: [MenuBarCandidate], displayID: CGDirectDisplayID,
          displayBounds: CGRect, menuBarBounds: CGRect, dividerX: CGFloat, start: CGPoint,
          generation: Int, alwaysHidden: Set<String>, ownPID: pid_t,
          minimumDividerX: CGFloat? = nil, maximumDividerX: CGFloat? = nil) {
        let actual = MenuBarAccessibility.candidates(candidates, on: displayBounds)
        guard !source.isSystemOwned, source.processIdentifier != ownPID,
              !alwaysHidden.contains(source.bundleIdentifier), source.frame.contains(start),
              actual.contains(where: { $0.id == source.id }),
              actual.filter({ $0.frame.contains(start) }).count == 1,
              LiveDividerDragSession.resolve(source, in: actual) != nil else { return nil }
        self.source = source
        self.displayID = displayID
        self.displayBounds = displayBounds
        self.menuBarBounds = menuBarBounds
        self.dividerX = dividerX
        self.initialDividerX = dividerX
        self.minimumDividerX = minimumDividerX ?? (displayBounds.minX + 5)
        self.maximumDividerX = maximumDividerX ?? (displayBounds.isEmpty ? .greatestFiniteMagnitude : displayBounds.maxX - 5)
        self.start = start
        self.generation = generation
    }

    mutating func shiftDivider(by distance: CGFloat) -> CGFloat {
        let previous = dividerX
        dividerX = min(max(dividerX + distance, minimumDividerX), maximumDividerX)
        return dividerX - previous
    }

    func preview(at point: CGPoint) -> MenuBarLayoutZone? {
        guard displayBounds.contains(point), menuBarBounds.insetBy(dx: 0, dy: -8).contains(point),
              abs(point.x - dividerX) > 2 else { return nil }
        return point.x < dividerX ? .hidden : .visible
    }

    func drop(at point: CGPoint, currentDisplay: CGDirectDisplayID, generation: Int,
              liveCandidates: [MenuBarCandidate]) -> (MenuBarCandidate, MenuBarLayoutZone)? {
        guard displayID == currentDisplay, self.generation == generation,
              hypot(point.x - start.x, point.y - start.y) > 5,
              let zone = preview(at: point),
              let current = LiveDividerDragSession.resolve(source,
                in: MenuBarAccessibility.candidates(liveCandidates, on: displayBounds)) else { return nil }
        return (current, zone)
    }
}

/// Records actual crossings rather than treating each mouse sample as a move.
struct LiveCrossingState {
    private(set) var side: MenuBarLayoutZone?
    init(initialSide: MenuBarLayoutZone?) { side = initialSide }
    mutating func cross(to newSide: MenuBarLayoutZone?) -> MenuBarLayoutZone? {
        guard let newSide, newSide != side else { return nil }
        defer { side = newSide }
        return side == nil ? nil : newSide
    }
}

@MainActor
final class LiveMenuBarEditor {
    private let access: MenuBarAccessibility
    private let layout: MenuBarLayoutController
    private let onBegin: () -> Void
    private let onEnd: () -> Void
    private let onCommit: () -> Void
    private let filter = MenuBarMouseFilter()
    private var requestedActive = false
    private var editing = false
    private var generation = 0
    private var displayID: CGDirectDisplayID?
    private var snapshot: [MenuBarCandidate] = []
    private var markerFrame = CGRect.zero
    private var markerPanel: LiveEditorPanel?
    private var markerView: LiveDividerMarkerView?
    private var ghostPanel: LiveEditorPanel?
    private var ghostSize = CGSize(width: 24, height: 24)
    private var reflowSurface: LiveMenuBarReflowSurface?
    private var reflowPanel: LiveEditorPanel?
    private var reflowView: LiveMenuBarReflowView?
    private var surfaceCapturePending = false
    private var surfaceRevision = 0
    private var visualRevision = 0
    private var settling = false
    private var session: LiveIconDragSession?
    private var crossing = LiveCrossingState(initialSide: nil)
    private var lastRefresh = Date.distantPast
    private var refreshPending = false
    var onInputAvailabilityChanged: ((Bool) -> Void)?
    var onBlankMouseDown: ((CGPoint) -> Void)?

    var isBusy: Bool { session != nil || filter.routing.captured || settling }

    init(access: MenuBarAccessibility, layout: MenuBarLayoutController,
         onBegin: @escaping () -> Void, onEnd: @escaping () -> Void, onCommit: @escaping () -> Void) {
        self.access = access
        self.layout = layout
        self.onBegin = onBegin
        self.onEnd = onEnd
        self.onCommit = onCommit
        filter.onCapturedEvent = { [weak self] type, point in
            guard let self else { return }
            switch type {
            case .leftMouseDown: self.beginDrag(at: point)
            case .leftMouseDragged: self.moveDrag(at: point)
            case .leftMouseUp: self.endDrag(at: point)
            default: break
            }
        }
        filter.onPassedLeftDown = { [weak self] in self?.onBlankMouseDown?($0) }
        filter.onAvailabilityChanged = { [weak self] available in
            guard let self else { return }
            self.onInputAvailabilityChanged?(available)
            if !available {
                self.filter.routing.editing = false
                self.session = nil
                self.close()
            }
        }
    }

    @discardableResult
    func prepareInput() -> Bool { filter.prepare() }

    func update(isActive: Bool, pointer: CGPoint?, shortcut: Int) {
        requestedActive = isActive
        filter.routing.shortcut = shortcut
        if isActive && !editing {
            guard prepareInput() else { return }
            // Only real, managed icon frames become hit targets once scanned.
            // The separator remains absent until those targets are protected.
            filter.routing.menuBarRegions = []
            filter.routing.editing = true
            editing = true
            onBegin()
            layout.beginLiveDividerEditing()
            if let pointer { selectDisplay(at: pointer, delay: 0.12) }
        }
        if !isActive && !isBusy { close(); return }
        guard isActive, !isBusy, let pointer else { return }
        selectDisplay(at: pointer)
        if Date().timeIntervalSince(lastRefresh) >= 2 { refreshDisplay() }
    }

    private func selectDisplay(at point: CGPoint, delay: TimeInterval = 0) {
        var selected: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &selected, &count) == .success,
              count == 1, selected != displayID else { return }
        generation += 1
        displayID = selected
        filter.routing.menuBarRegions = []
        access.selectDisplay(selected)
        markerPanel?.orderOut(nil)
        markerFrame = .zero
        surfaceRevision += 1
        reflowSurface = nil
        surfaceCapturePending = false
        snapshot = []
        refreshPending = false
        lastRefresh = Date()
        refreshDisplay(delay: delay)
    }

    private func refreshDisplay(delay: TimeInterval = 0) {
        guard editing, !isBusy, !refreshPending, let display = displayID else { return }
        refreshPending = true
        lastRefresh = Date()
        let token = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.editing, token == self.generation else { return }
            self.access.refresh(afterCapture: { [weak self] in
                guard let self, self.editing, token == self.generation, self.displayID == display else { return }
                self.refreshPending = false
                if !self.isBusy { self.configureFromLiveScan() }
            }, completion: { [weak self] in
                guard let self, self.editing, token == self.generation, !self.isBusy else { return }
                self.configureFromLiveScan()
            })
        }
    }

    private func configureFromLiveScan() {
        guard let display = displayID, let screen = screen(for: display),
              let bar = menuBarRect(on: screen), filter.isAvailable else { markerPanel?.orderOut(nil); return }
        let bounds = CGDisplayBounds(display)
        snapshot = MenuBarAccessibility.candidates(access.liveItems, on: bounds)
        guard let firstSystemX = snapshot.filter(\.isSystemOwned).map(\.frame.minX).min(),
              firstSystemX - 5 >= bounds.minX + 5 else { markerPanel?.orderOut(nil); return }
        filter.routing.menuBarRegions = snapshot.filter {
            !$0.isSystemOwned && $0.processIdentifier != getpid() && !layout.isAlwaysHidden($0)
        }.map(\.frame)
        let apps = snapshot.filter { !$0.isSystemOwned && $0.processIdentifier != getpid() && !layout.isAlwaysHidden($0) }
        let hiddenRight = apps.filter { layout.isHidden($0) }.map(\.frame.maxX).max()
        let preferred = hiddenRight.map { $0 + 5 }
            ?? apps.map(\.frame.minX).min().map { $0 - 5 } ?? (firstSystemX - 5)
        let dividerX = min(max(markerFrame.isEmpty ? preferred : markerFrame.midX, bounds.minX + 5), firstSystemX - 5)
        markerFrame = CGRect(x: dividerX - 4.5, y: bounds.minY, width: 9, height: bar.height)
        if markerPanel == nil {
            let panel = LiveEditorPanel(frame: .zero, levelOffset: 2)
            let view = LiveDividerMarkerView()
            panel.contentView = view
            markerView = view
            markerPanel = panel
        }
        markerView?.setState(nil, dragging: false)
        let wasVisible = markerPanel?.isVisible == true
        let barFrame = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bar.height)
        markerPanel?.setFrame(appKitRect(barFrame, screen: screen, display: display), display: true)
        markerView?.setDividerPosition(dividerX - bounds.minX, animated: false)
        if !wasVisible { markerPanel?.alphaValue = 0 }
        markerPanel?.orderFrontRegardless()
        if !wasVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                self.markerPanel?.animator().alphaValue = 1
            }
        }
        prepareReflowSurface(display: display, bar: bar, firstSystemX: firstSystemX)
    }

    private func prepareReflowSurface(display: CGDirectDisplayID,
                                      bar: CGRect, firstSystemX: CGFloat) {
        let apps = snapshot.filter { !$0.isSystemOwned && !$0.isLiveDivider && !layout.isAlwaysHidden($0) }
        let signature = LiveMenuBarReflowSurface.signature(for: apps)
        guard !surfaceCapturePending, reflowSurface?.signature != signature,
              let firstAppX = apps.map(\.frame.minX).min() else { return }
        let bounds = CGDisplayBounds(display)
        let menuEnd = NSWorkspace.shared.frontmostApplication.map {
            MenuBarAccessibility.applicationMenuBarFrames(processIdentifier: $0.processIdentifier)
                .filter { bounds.contains(CGPoint(x: $0.midX, y: $0.midY)) }.map(\.maxX).max()
        } ?? nil
        let maximumSlot = apps.map(\.width).max() ?? 24
        // Never mask application menus or the first immovable system item.
        let left = max(bounds.minX + 1, menuEnd.map { $0 + 2 } ?? firstAppX - 2,
                       firstAppX - maximumSlot - 4)
        let right = firstSystemX - 1
        let region = CGRect(x: left, y: bounds.minY, width: right - left, height: bar.height)
        guard region.width > 4 else { return }
        let images = Dictionary(uniqueKeysWithValues: apps.compactMap { item in
            access.layoutImage(for: item).map { (item.id, $0) }
        })
        let excluded = Set([markerPanel, ghostPanel, reflowPanel].compactMap { panel in
            panel.map { CGWindowID($0.windowNumber) }
        })
        surfaceCapturePending = true
        surfaceRevision += 1
        let revision = surfaceRevision, token = generation
        Task { @MainActor [weak self] in
            let surface = await LiveMenuBarReflowSurface.capture(displayID: display, region: region,
                candidates: apps, images: images, excludingWindows: excluded)
            guard let self, revision == self.surfaceRevision else { return }
            self.surfaceCapturePending = false
            guard self.editing, token == self.generation, self.displayID == display, !self.isBusy else { return }
            self.reflowSurface = surface
        }
    }

    private func beginDrag(at point: CGPoint) {
        guard editing, requestedActive, session == nil, !settling, let display = displayID,
              !markerFrame.isEmpty, let screen = screen(for: display), let bar = menuBarRect(on: screen) else { return }
        let matches = snapshot.filter { $0.frame.contains(point) }
        guard matches.count == 1, let source = matches.first,
              let image = access.layoutImage(for: source) else { return }
        let bounds = CGDisplayBounds(display)
        let firstSystemX = snapshot.filter(\.isSystemOwned).map(\.frame.minX).min() ?? bounds.maxX
        session = LiveIconDragSession(source: source, candidates: snapshot, displayID: display,
            displayBounds: bounds, menuBarBounds: CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bar.height),
            dividerX: markerFrame.midX, start: point, generation: generation,
            alwaysHidden: layout.alwaysHiddenBundleIDs, ownPID: getpid(),
            minimumDividerX: bounds.minX + 5, maximumDividerX: firstSystemX - 5)
        guard let session else { return }
        visualRevision += 1
        crossing = LiveCrossingState(initialSide: session.preview(at: point))
        let apps = snapshot.filter { !$0.isSystemOwned && !$0.isLiveDivider && !layout.isAlwaysHidden($0) }
        if let surface = reflowSurface,
           surface.signature == LiveMenuBarReflowSurface.signature(for: apps),
           surface.region.contains(source.frame),
           let view = surface.makeView(source: source) {
            let overlay = LiveEditorPanel(frame: appKitRect(surface.region, screen: screen, display: display), levelOffset: 1)
            overlay.contentView = view
            reflowView = view
            reflowPanel = overlay
            overlay.orderFrontRegardless()
        }
        let panel = LiveEditorPanel(frame: .zero, levelOffset: 3)
        let imageView = NSImageView()
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = .labelColor
        panel.contentView = imageView
        let fit = min(1, min(source.width / max(image.size.width, 1), source.height / max(image.size.height, 1)))
        ghostSize = CGSize(width: image.size.width * fit, height: image.size.height * fit)
        ghostPanel = panel
        moveDrag(at: point)
    }

    private func moveDrag(at point: CGPoint) {
        guard let drag = session, let screen = screen(for: drag.displayID) else { return }
        let side = drag.preview(at: point)
        markerView?.setState(side, dragging: true)
        if let transition = crossing.cross(to: side) {
            // Move the line by this icon's native slot, opposite to its drag.
            // It remains ahead of the system icons and becomes the next hit boundary.
            let slot = max(8, min(drag.source.frame.width, 96))
            let delta = transition == .hidden ? slot : -slot
            if let session {
                var shifted = session
                let actualDelta = shifted.shiftDivider(by: delta)
                self.session = shifted
                if actualDelta != 0 {
                    markerFrame.origin.x += actualDelta
                    let start = CACurrentMediaTime()
                    markerView?.setDividerPosition(markerFrame.midX - drag.displayBounds.minX, animated: true, start: start)
                    reflowView?.moveNeighbours(displacement: shifted.dividerX - shifted.initialDividerX, start: start)
                }
            }
            layout.applyLiveVisibility(drag.source, to: transition, sourceSnapshot: snapshot)
        }
        guard drag.displayBounds.contains(point) else { ghostPanel?.orderOut(nil); return }
        let p = appKitPoint(point, screen: screen, display: drag.displayID)
        ghostPanel?.setFrame(CGRect(x: p.x - ghostSize.width / 2, y: p.y - ghostSize.height / 2,
                                   width: ghostSize.width, height: ghostSize.height), display: true)
        ghostPanel?.orderFrontRegardless()
    }

    private func endDrag(at point: CGPoint) {
        if let drag = session {
            moveDrag(at: point)
            session = nil
            ghostPanel?.orderOut(nil)
            markerView?.setState(nil, dragging: false)
            onCommit()
            if reflowView != nil {
                settling = true
                let revision = visualRevision
                settleVisualDrag(display: drag.displayID, revision: revision, attempt: 0)
                // Always release the visual cover even if AX/permissions stop responding.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                    guard let self, self.settling, self.visualRevision == revision else { return }
                    self.finishVisualDrag()
                }
                return
            }
        }
        if !requestedActive { close() }
        else { refreshDisplay(delay: 0.12) }
    }

    private func settleVisualDrag(display: CGDirectDisplayID, revision: Int, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            guard let self, self.settling, self.visualRevision == revision,
                  self.displayID == display else { return }
            if self.layout.isMovingItem && attempt < 5 {
                self.settleVisualDrag(display: display, revision: revision, attempt: attempt + 1)
                return
            }
            self.access.refresh { [weak self] in
                guard let self, self.settling, self.visualRevision == revision,
                      self.access.displayID == display else { return }
                self.reflowView?.settle(to: self.access.liveItems, start: CACurrentMediaTime())
                DispatchQueue.main.asyncAfter(deadline: .now() + LiveMenuBarMotion.duration) { [weak self] in
                    guard let self, self.settling, self.visualRevision == revision else { return }
                    self.finishVisualDrag()
                }
            }
        }
    }

    private func finishVisualDrag() {
        settling = false
        reflowPanel?.orderOut(nil)
        reflowPanel = nil
        reflowView = nil
        reflowSurface = nil
        if !requestedActive { close() }
        else { refreshDisplay() }
    }

    private func close() {
        filter.routing.editing = false
        guard editing else { return }
        generation += 1
        editing = false
        refreshPending = false
        displayID = nil
        snapshot = []
        markerFrame = .zero
        visualRevision += 1
        surfaceRevision += 1
        settling = false
        surfaceCapturePending = false
        reflowSurface = nil
        reflowView = nil
        reflowPanel?.orderOut(nil)
        reflowPanel = nil
        markerPanel?.orderOut(nil)
        ghostPanel?.orderOut(nil)
        layout.endLiveDividerEditing()
        onEnd()
    }

    private func screen(for display: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display
        }
    }
    private func menuBarRect(on screen: NSScreen) -> CGRect? {
        let measured = screen.frame.maxY - screen.visibleFrame.maxY
        let height = measured > 0 ? measured : max(NSStatusBar.system.thickness, screen.safeAreaInsets.top)
        guard height > 0, height <= screen.frame.height / 4 else { return nil }
        return CGRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width, height: height)
    }
    private func appKitPoint(_ point: CGPoint, screen: NSScreen, display: CGDirectDisplayID) -> CGPoint {
        let bounds = CGDisplayBounds(display)
        return CGPoint(x: screen.frame.minX + point.x - bounds.minX, y: screen.frame.maxY - point.y + bounds.minY)
    }
    private func appKitRect(_ rect: CGRect, screen: NSScreen, display: CGDirectDisplayID) -> CGRect {
        CGRect(origin: appKitPoint(CGPoint(x: rect.minX, y: rect.maxY), screen: screen, display: display), size: rect.size)
    }
}

@MainActor
private final class LiveEditorPanel: NSPanel {
    init(frame: CGRect, levelOffset: Int) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + levelOffset)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class LiveDividerMarkerView: NSView {
    private let stroke = CALayer()
    private var state: MenuBarLayoutZone?
    private var dragging = false
    private var dividerCenterX: CGFloat = 0
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        stroke.cornerRadius = 0.75
        layer?.addSublayer(stroke)
    }
    required init?(coder: NSCoder) { nil }
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let height: CGFloat = dragging ? 17 : 14
        stroke.frame = CGRect(x: dividerCenterX - 0.75, y: bounds.midY - height / 2, width: 1.5, height: height)
        CATransaction.commit()
    }
    func setDividerPosition(_ x: CGFloat, animated: Bool, start: CFTimeInterval = CACurrentMediaTime()) {
        guard abs(x - dividerCenterX) > 0.1 else { return }
        let current = stroke.presentation()?.position ?? stroke.position
        dividerCenterX = x
        needsLayout = true
        layoutSubtreeIfNeeded()
        guard animated else { return }
        let target = stroke.position
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stroke.position = current
        CATransaction.commit()
        LiveMenuBarMotion.move(stroke, to: target, start: start)
    }
    func setState(_ state: MenuBarLayoutZone?, dragging: Bool) {
        guard self.state != state || self.dragging != dragging || stroke.backgroundColor == nil else { return }
        self.state = state
        self.dragging = dragging
        let color: NSColor = dragging ? (state == .visible ? .systemGreen : .systemBlue) : .labelColor
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        stroke.backgroundColor = color.withAlphaComponent(dragging ? 1 : 0.7).cgColor
        stroke.shadowColor = color.cgColor
        stroke.shadowOpacity = dragging ? 0.35 : 0
        stroke.shadowRadius = dragging ? 3 : 0
        stroke.shadowOffset = .zero
        CATransaction.commit()
        needsLayout = true
    }
}
