// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import ApplicationServices
import CoreGraphics
import QuartzCore

struct ClockTarget: Equatable {
    let display: UInt32
    let point: CGPoint
}

enum ClockRelayEffect: Equatable {
    case releaseRestriction
    case replay(ClockTarget)
    case restoreRestriction
    case finished
    case reportFailure
}

/// A bounded lease for one physical clock click. No visual cover is used.
struct ClockRelayState {
    enum Phase: Equatable { case idle, releasing, waitingForPanel, restoring }
    private(set) var phase = Phase.idle
    private(set) var ticket: UInt64 = 0
    private var target: ClockTarget?
    private var beganAt: TimeInterval = 0
    private var releasedAt: TimeInterval?
    private var replayedAt: TimeInterval?
    private var pressCompleted = false
    private var initialPanelVisible = false
    private var panelChangedAt: TimeInterval?

    mutating func begin(_ target: ClockTarget, now: TimeInterval, panelVisible: Bool) -> [ClockRelayEffect] {
        guard phase == .idle else { return [] }
        ticket += 1
        self.target = target
        beganAt = now
        releasedAt = nil
        replayedAt = nil
        panelChangedAt = nil
        pressCompleted = false
        initialPanelVisible = panelVisible
        phase = .releasing
        return [.releaseRestriction]
    }

    mutating func completePress() {
        guard phase == .releasing else { return }
        pressCompleted = true
    }

    mutating func released(ticket: UInt64, now: TimeInterval) {
        guard ticket == self.ticket, phase == .releasing, releasedAt == nil else { return }
        releasedAt = now
    }

    mutating func restored(ticket: UInt64) -> [ClockRelayEffect] {
        guard ticket == self.ticket, phase == .restoring else { return [] }
        phase = .idle
        return [.finished]
    }

    mutating func tick(now: TimeInterval, panelVisible: Bool) -> [ClockRelayEffect] {
        guard phase != .idle else { return [] }
        if now - beganAt >= 4 {
            phase = .idle
            return [.restoreRestriction, .finished, .reportFailure]
        }
        if phase == .releasing, pressCompleted, let releasedAt,
           now - releasedAt >= 0.06, let target {
            replayedAt = now
            phase = .waitingForPanel
            return [.replay(target)]
        }
        if phase == .waitingForPanel, let replayedAt {
            if panelVisible != initialPanelVisible {
                if panelChangedAt == nil { panelChangedAt = now }
                // Keep the half-second release from the previously working
                // behavior, then restore after the system panel settles.
                if now - replayedAt >= 0.5, now - panelChangedAt! >= 0.15 {
                    phase = .restoring
                    return [.restoreRestriction]
                }
            } else {
                panelChangedAt = nil
            }
            if now - replayedAt >= 1.2 {
                phase = .restoring
                return [.restoreRestriction, .reportFailure]
            }
        }
        return []
    }

    mutating func cancel() -> [ClockRelayEffect] {
        guard phase != .idle else { return [] }
        phase = .idle
        return [.restoreRestriction, .finished]
    }
}

/// Retains the confirmed whole-click relay, without screenshot capture,
/// background windows, masking, or any native icon reorder operation.
@MainActor
final class ClockClickBridge {
    private struct ClockHit {
        let target: ClockTarget
        let bounds: CGRect
    }
    private struct Press {
        let hit: ClockHit
        let time: CFTimeInterval
        let startsLease: Bool
        var cancelled = false
    }
    private static let stamp: Int64 = 0x4E_69_6D_42_61_72_4E_43
    private let layout: MenuBarLayoutController
    private let onBegin: () -> Void
    private let onEnd: () -> Void
    private var model = ClockRelayState()
    private var press: Press?
    private var hits: [ClockHit] = []
    private var scannedAt = Date.distantPast
    private var nextRefresh = Date.distantPast
    private var refreshing = false
    private var leaseActive = false
    private var queued: [ClockTarget] = []
    private var timer: Timer?
    var isBusy: Bool { model.phase != .idle }

    init(layout: MenuBarLayoutController, onBegin: @escaping () -> Void, onEnd: @escaping () -> Void) {
        self.layout = layout
        self.onBegin = onBegin
        self.onEnd = onEnd
    }

    func refreshIfNeeded() {
        guard !isBusy, !refreshing, layout.canBridgeClock, AXIsProcessTrusted(), Date() >= nextRefresh else { return }
        nextRefresh = Date().addingTimeInterval(1)
        refreshing = true
        Task { [weak self] in
            let items = await Task.detached(priority: .utility) { MenuBarAccessibility.enumerateMenuExtras() }.value
            guard let self else { return }
            self.refreshing = false
            guard !self.isBusy else { return }
            self.hits = NSScreen.screens.flatMap { screen -> [ClockHit] in
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return [] }
                let id = number.uint32Value
                let bounds = CGDisplayBounds(id)
                return MenuBarAccessibility.candidates(items, on: bounds)
                    .filter { $0.isSystemOwned && $0.isClock }
                    .map { ClockHit(target: ClockTarget(display: id, point: CGPoint(x: $0.frame.midX, y: $0.frame.midY)), bounds: $0.frame) }
            }
            self.scannedAt = Date()
        }
    }

    func route(_ type: CGEventType, event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.eventSourceUserData) != Self.stamp else { return false }
        let flags = event.flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn])
        if type == .leftMouseDragged, var press {
            if hypot(event.location.x - press.hit.target.point.x, event.location.y - press.hit.target.point.y) > 4 { press.cancelled = true }
            self.press = press
            return true
        }
        if type == .leftMouseUp, let press {
            self.press = nil
            let valid = !press.cancelled && flags.isEmpty && press.hit.bounds.contains(event.location)
                && CACurrentMediaTime() - press.time < 1
            if valid {
                if press.startsLease && model.phase == .releasing { model.completePress() }
                else if queued.count < 4 { queued.append(press.hit.target) }
            } else if press.startsLease && model.phase == .releasing { cancel() }
            return true
        }
        guard type == .leftMouseDown, flags.isEmpty, Date().timeIntervalSince(scannedAt) < 5,
              isBusy || layout.canBridgeClock else { return false }
        let matches = hits.filter { $0.bounds.contains(event.location) }
        guard matches.count == 1 else { return false }
        let target = ClockTarget(display: matches[0].target.display, point: event.location)
        let hit = ClockHit(target: target, bounds: matches[0].bounds)
        let startsLease = !isBusy
        guard isBusy || start(target) else { return false }
        press = Press(hit: hit, time: CACurrentMediaTime(), startsLease: startsLease)
        return true
    }

    @discardableResult
    private func start(_ target: ClockTarget, completed: Bool = false) -> Bool {
        guard !isBusy, layout.canBridgeClock else { return false }
        let effects = model.begin(target, now: CACurrentMediaTime(), panelVisible: panelPresenting())
        if completed { model.completePress() }
        onBegin()
        let ticket = model.ticket
        DispatchQueue.main.async { [weak self] in
            guard let self, self.model.ticket == ticket, self.isBusy else { return }
            self.apply(effects)
            self.startTimer()
        }
        return true
    }

    func cancel() {
        press = nil
        queued.removeAll()
        apply(model.cancel())
    }

    private func apply(_ effects: [ClockRelayEffect]) {
        for effect in effects {
            switch effect {
            case .releaseRestriction:
                guard layout.beginClockBridge() else { cancel(); return }
                leaseActive = true
                model.released(ticket: model.ticket, now: CACurrentMediaTime())
            case .replay(let target):
                guard AXIsProcessTrusted(), CGDisplayIsActive(target.display) != 0,
                      NSEvent.modifierFlags.intersection([.command, .option, .control, .shift, .function]).isEmpty,
                      let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: target.point, mouseButton: .left),
                      let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: target.point, mouseButton: .left) else { cancel(); return }
                for event in [down, up] {
                    event.flags = []
                    event.setIntegerValueField(.mouseEventClickState, value: 1)
                    event.setIntegerValueField(.eventSourceUserData, value: Self.stamp)
                    event.post(tap: .cghidEventTap)
                }
            case .restoreRestriction:
                let ticket = model.ticket
                guard leaseActive else { apply(model.restored(ticket: ticket)); continue }
                leaseActive = false
                layout.endClockBridge { [weak self] in
                    guard let self else { return }
                    self.apply(self.model.restored(ticket: ticket))
                }
            case .finished:
                timer?.invalidate()
                timer = nil
                nextRefresh = .distantPast
                onEnd()
                if !queued.isEmpty {
                    let target = queued.removeFirst()
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        if !self.start(target, completed: true) { self.queued.removeAll() }
                    }
                }
            case .reportFailure:
                NSLog("NimBar clock activation timed out; current visibility restored.")
            }
        }
    }

    private func startTimer() {
        guard isBusy, timer == nil else { return }
        let timer = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.apply(self.model.tick(now: CACurrentMediaTime(), panelVisible: self.panelPresenting()))
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func panelPresenting() -> Bool {
        let owners = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").map(\.processIdentifier))
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return false }
        return windows.contains {
            guard let pid = $0[kCGWindowOwnerPID as String] as? Int,
                  let layer = $0[kCGWindowLayer as String] as? Int,
                  let bounds = $0[kCGWindowBounds as String] as? [String: NSNumber],
                  let height = bounds["Height"]?.doubleValue else { return false }
            return owners.contains(pid_t(pid)) && layer > 0 && height > 300
        }
    }
}
