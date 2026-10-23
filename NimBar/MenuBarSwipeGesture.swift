// SPDX-License-Identifier: GPL-3.0-only
import AppKit

enum MenuBarSwipeDirection: String, CaseIterable, Identifiable, Sendable {
    case left, right
    var id: String { rawValue }
    var opposite: Self { self == .left ? .right : .left }
    var title: String { L10n.text(self == .left ? "Swipe a sinistra" : "Swipe a destra") }
}

/// Copy only the public scroll-event fields needed by the recognizer. The
/// event itself is never retained or consumed by the global/local monitors.
struct MenuBarSwipeSample: Sendable {
    let x: Double
    let y: Double
    let precise: Bool
    let phased: Bool
    let inverted: Bool
    let began: Bool
    let ended: Bool
    let cancelled: Bool
    let momentum: Bool
    let timestamp: TimeInterval
    let location: CGPoint

    init(event: NSEvent, location: CGPoint) {
        x = event.scrollingDeltaX
        y = event.scrollingDeltaY
        precise = event.hasPreciseScrollingDeltas
        phased = !event.phase.isEmpty
        inverted = event.isDirectionInvertedFromDevice
        began = event.phase.contains(.began)
        ended = event.phase.contains(.ended)
        cancelled = event.phase.contains(.cancelled)
        momentum = !event.momentumPhase.isEmpty
        timestamp = event.timestamp
        self.location = location
    }

    init(x: Double, y: Double = 0, precise: Bool = true, phased: Bool = false, inverted: Bool = false,
         began: Bool = false, ended: Bool = false, cancelled: Bool = false,
         momentum: Bool = false, timestamp: TimeInterval, location: CGPoint = .zero) {
        self.x = x; self.y = y; self.precise = precise; self.inverted = inverted
        self.phased = phased || began || ended || cancelled
        self.began = began; self.ended = ended; self.cancelled = cancelled
        self.momentum = momentum; self.timestamp = timestamp; self.location = location
    }
}

struct MenuBarSwipeIntent: Equatable {
    let direction: MenuBarSwipeDirection
    let origin: CGPoint
    let displayID: UInt32
}

/// Hardware-independent gesture state. A stroke stays bound to its starting
/// display and point, even when showing/hiding changes menu-bar geometry.
struct MenuBarSwipeRecognizer {
    private var origin: CGPoint?
    private var displayID: UInt32?
    private var lastTimestamp: TimeInterval?
    private var totalX: Double = 0
    private var travelX: Double = 0
    private var travelY: Double = 0
    private var finished = false

    mutating func reset() { self = Self() }

    mutating func consume(_ sample: MenuBarSwipeSample, displayID: UInt32?,
                          isOverMenuBar: Bool) -> MenuBarSwipeIntent? {
        // Momentum is part of the previous stroke, not another opportunity to fire.
        guard !sample.momentum else { return nil }
        if sample.began || (!sample.phased && lastTimestamp.map({ sample.timestamp - $0 > 0.3 }) == true) {
            reset()
        }
        lastTimestamp = sample.timestamp
        defer { if sample.ended || sample.cancelled { reset() } }
        guard !sample.cancelled, !finished else { return nil }
        guard isOverMenuBar, let displayID else { finished = true; return nil }
        if let startingDisplay = self.displayID, startingDisplay != displayID {
            finished = true
            return nil
        }
        if origin == nil {
            origin = sample.location
            self.displayID = displayID
        }
        guard sample.x != 0 || sample.y != 0 else { return nil }
        totalX += sample.inverted ? -sample.x : sample.x
        travelX += abs(sample.x)
        travelY += abs(sample.y)
        let threshold = sample.precise ? 18.0 : 1.0
        // A vertical scroll cannot become a swipe after a small sideways wobble.
        if travelY >= threshold && travelY > travelX { finished = true; return nil }
        guard abs(totalX) >= threshold, travelX > travelY * 1.5,
              let origin else { return nil }
        finished = true
        return MenuBarSwipeIntent(direction: totalX > 0 ? .left : .right,
                                  origin: origin, displayID: displayID)
    }
}
