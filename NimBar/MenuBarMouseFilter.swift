// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import CoreGraphics

/// Pure routing policy: a captured edit gesture never becomes a native
/// Command-drag, even after the shortcut is released or the pointer leaves.
struct MenuBarMouseRouting {
    var shortcut = 3
    var editing = false
    var menuBarRegions: [CGRect] = []
    private(set) var captured = false

    mutating func shouldConsume(_ type: CGEventType, point: CGPoint, modifiers: Int) -> Bool {
        if captured {
            if type == .leftMouseUp { captured = false }
            return type == .leftMouseDown || type == .leftMouseDragged || type == .leftMouseUp
        }
        guard type == .leftMouseDown, editing, modifiers == shortcut,
              menuBarRegions.contains(where: { $0.contains(point) }) else { return false }
        captured = true
        return true
    }
}

@MainActor
final class MenuBarMouseFilter {
    var routing = MenuBarMouseRouting()
    var onCapturedEvent: ((CGEventType, CGPoint) -> Void)?
    var onPassedLeftDown: ((CGPoint) -> Void)?
    var onAvailabilityChanged: ((Bool) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var lastAttempt = Date.distantPast

    var isAvailable: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    @discardableResult
    func prepare() -> Bool {
        if let tap {
            if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
            return CGEvent.tapIsEnabled(tap: tap)
        }
        guard AXIsProcessTrusted(), Date().timeIntervalSince(lastAttempt) > 2 else { return false }
        lastAttempt = Date()
        let mask = [CGEventType.leftMouseDown, .leftMouseDragged, .leftMouseUp]
            .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask,
            callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                // This port is installed exclusively on the main run loop.
                let consumed = MainActor.assumeIsolated {
                    Unmanaged<MenuBarMouseFilter>.fromOpaque(info).takeUnretainedValue().route(type, event: event)
                }
                return consumed ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            onAvailabilityChanged?(false)
            return false
        }
        tap = port
        source = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        onAvailabilityChanged?(isAvailable)
        return isAvailable
    }

    private func route(_ type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onAvailabilityChanged?(self.isAvailable)
            }
            return false
        }
        let point = event.location
        let flags = event.flags
        let modifiers = (flags.contains(.maskCommand) ? 1 : 0) | (flags.contains(.maskAlternate) ? 2 : 0)
            | (flags.contains(.maskControl) ? 4 : 0) | (flags.contains(.maskShift) ? 8 : 0)
        // No AX, screenshots, file access, UI rendering or waits in this path.
        if routing.shouldConsume(type, point: point, modifiers: modifiers) {
            DispatchQueue.main.async { [weak self] in self?.onCapturedEvent?(type, point) }
            return true
        }
        if type == .leftMouseDown {
            DispatchQueue.main.async { [weak self] in self?.onPassedLeftDown?(point) }
        }
        return false
    }
}
