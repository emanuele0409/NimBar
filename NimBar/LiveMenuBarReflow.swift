// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import QuartzCore
import ScreenCaptureKit

/// Positions are visual only. Neighbours retain their relative native order;
/// moving the hole left/right never issues a native reorder operation.
struct LiveMenuBarReflowPlan {
    let source: MenuBarCandidate
    let neighbours: [MenuBarCandidate]
    let bounds: CGRect

    func frames(displacement: CGFloat) -> [String: CGRect] {
        let eligible = neighbours.filter { !$0.isSystemOwned && $0.id != source.id && bounds.contains($0.frame) }
        let moving = eligible.filter { $0.frame.maxX <= source.frame.minX + 0.5 }
        let minimum = moving.map(\.frame.minX).min() ?? bounds.minX
        let maximum = moving.map(\.frame.maxX).max() ?? bounds.maxX
        let offset = min(max(displacement, bounds.minX - minimum), bounds.maxX - maximum)
        return Dictionary(uniqueKeysWithValues: eligible.map { item in
            let frame = item.frame.maxX <= source.frame.minX + 0.5
                ? item.frame.offsetBy(dx: offset, dy: 0) : item.frame
            return (item.id, frame)
        })
    }
}

@MainActor
enum LiveMenuBarMotion {
    static let duration: TimeInterval = 0.30

    static func move(_ layer: CALayer, to point: CGPoint, start: CFTimeInterval) {
        let current = layer.presentation()?.position ?? layer.position
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.position = point
        CATransaction.commit()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              hypot(current.x - point.x, current.y - point.y) > 0.1 else {
            layer.removeAnimation(forKey: "menu-bar-motion")
            return
        }
        let motion = CASpringAnimation(keyPath: "position")
        motion.fromValue = NSValue(point: current)
        motion.toValue = NSValue(point: point)
        motion.mass = 1
        motion.stiffness = 360
        motion.damping = 36
        motion.initialVelocity = 0
        motion.duration = duration
        motion.beginTime = layer.convertTime(start, from: nil)
        layer.add(motion, forKey: "menu-bar-motion")
    }
}

/// Restore just the empty bar pixels under temporary icon copies. The source
/// screenshot is never persisted and no application/system-menu area is masked.
enum LiveMenuBarBackdrop {
    static func clearingSlots(in image: CGImage, region: CGRect, slots: [CGRect]) -> CGImage? {
        let width = image.width, height = image.height
        guard width > 2, height > 0, region.width > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let scale = CGFloat(width) / region.width
        var intervals: [ClosedRange<Int>] = []
        for slot in slots {
            let frame = slot.intersection(region)
            guard !frame.isNull, frame.width > 0 else { continue }
            let left = max(0, Int(floor((frame.minX - region.minX) * scale)))
            let right = min(width - 1, Int(ceil((frame.maxX - region.minX) * scale)) - 1)
            guard left <= right else { continue }
            intervals.append(left...right)
        }
        var merged: [ClosedRange<Int>] = []
        for interval in intervals.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, interval.lowerBound <= last.upperBound + 1 {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, interval.upperBound)
            } else { merged.append(interval) }
        }
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        for interval in merged {
            // Without clean edge samples, keep the real bar instead of drawing
            // a guessed solid patch that could cover another menu item.
            guard interval.lowerBound > 0, interval.upperBound < width - 1 else { return nil }
            let left = interval.lowerBound - 1, right = interval.upperBound + 1
            for y in 0..<height {
                for channel in 0..<4 {
                    let a = Double(pixels[(y * width + left) * 4 + channel])
                    let b = Double(pixels[(y * width + right) * 4 + channel])
                    for x in interval {
                        let fraction = Double(x - left) / Double(right - left)
                        pixels[(y * width + x) * 4 + channel] = UInt8((a + (b - a) * fraction).rounded())
                    }
                }
            }
        }
        return context.makeImage()
    }
}

@MainActor
struct LiveMenuBarReflowSurface {
    let region: CGRect
    let candidates: [MenuBarCandidate]
    let images: [String: NSImage]
    let screenshot: CGImage
    let scale: CGFloat
    let signature: String

    static func signature(for items: [MenuBarCandidate]) -> String {
        items.map { "\($0.id):\($0.frame)" }.joined(separator: "|")
    }

    static func capture(displayID: CGDirectDisplayID, region: CGRect,
                        candidates: [MenuBarCandidate], images: [String: NSImage],
                        excludingWindows: Set<CGWindowID>) async -> Self? {
        guard CGPreflightScreenCaptureAccess(), region.width > 4, region.height > 0,
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.displayID == displayID }) else { return nil }
        let excluded = content.windows.filter { excludingWindows.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let config = SCStreamConfiguration()
        let bounds = CGDisplayBounds(displayID)
        let scale = max(2, CGFloat(filter.pointPixelScale))
        config.sourceRect = region.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
        config.width = Int((region.width * scale).rounded())
        config.height = Int((region.height * scale).rounded())
        config.showsCursor = false
        config.captureResolution = .best
        config.ignoreShadowsDisplay = true
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { return nil }
        return Self(region: region, candidates: candidates, images: images, screenshot: image,
                    scale: scale, signature: signature(for: candidates))
    }

    func makeView(source: MenuBarCandidate) -> LiveMenuBarReflowView? {
        let sprites = candidates.filter { images[$0.id] != nil && region.contains($0.frame) }
        // The marker window is excluded from capture. Its slot may touch the
        // system boundary, so never erase that boundary as an icon cell.
        let slots = sprites.map(\.frame) + [source.frame]
        guard let background = LiveMenuBarBackdrop.clearingSlots(in: screenshot, region: region, slots: slots) else { return nil }
        return LiveMenuBarReflowView(surface: self, background: background, source: source, sprites: sprites)
    }
}

@MainActor
final class LiveMenuBarReflowView: NSView {
    private let region: CGRect
    private let items: [MenuBarCandidate]
    private var sprites: [String: CALayer] = [:]
    private let plan: LiveMenuBarReflowPlan

    init(surface: LiveMenuBarReflowSurface, background: CGImage, source: MenuBarCandidate,
         sprites items: [MenuBarCandidate]) {
        region = surface.region
        self.items = items
        plan = LiveMenuBarReflowPlan(source: source, neighbours: self.items, bounds: surface.region)
        super.init(frame: CGRect(origin: .zero, size: surface.region.size))
        wantsLayer = true
        guard let root = layer else { return }
        root.masksToBounds = true
        let backdrop = CALayer()
        backdrop.frame = bounds
        backdrop.contents = background
        backdrop.contentsScale = surface.scale
        root.addSublayer(backdrop)
        for item in self.items {
            guard let image = surface.images[item.id],
                  let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            let sprite = CALayer()
            sprite.isHidden = item.id == source.id
            sprite.contents = bitmap
            sprite.contentsScale = surface.scale
            sprite.contentsGravity = .resizeAspect
            let fit = min(1, min(item.width / max(image.size.width, 1), item.height / max(image.size.height, 1)))
            let size = CGSize(width: image.size.width * fit, height: image.size.height * fit)
            sprite.bounds = CGRect(origin: .zero, size: size)
            sprite.position = localCenter(item.frame)
            root.addSublayer(sprite)
            self.sprites[item.id] = sprite
        }
    }
    required init?(coder: NSCoder) { nil }

    private func localCenter(_ frame: CGRect) -> CGPoint {
        CGPoint(x: frame.midX - region.minX, y: region.maxY - frame.midY)
    }

    func moveNeighbours(displacement: CGFloat, start: CFTimeInterval) {
        for (id, frame) in plan.frames(displacement: displacement) {
            if let layer = sprites[id] { LiveMenuBarMotion.move(layer, to: localCenter(frame), start: start) }
        }
    }

    func settle(to liveCandidates: [MenuBarCandidate], start: CFTimeInterval) {
        for item in items {
            guard let sprite = sprites[item.id],
                  let current = LiveDividerDragSession.resolve(item, in: liveCandidates),
                  region.contains(current.frame) else { continue }
            sprite.isHidden = false
            LiveMenuBarMotion.move(sprite, to: localCenter(current.frame), start: start)
        }
    }
}
