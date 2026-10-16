// Build-time artwork: a Retina canvas with a centred installation arrow.
import AppKit
let destination = CommandLine.arguments[1]
let size = NSSize(width: 582, height: 300)
let image = NSImage(size: size)
let representation = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1164, pixelsHigh: 600,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
representation.size = size
image.addRepresentation(representation)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
NSColor.white.setFill()
NSRect(origin: .zero, size: size).fill()
let arrow = NSBezierPath()
arrow.lineWidth = 3
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 269, y: 150))
arrow.line(to: NSPoint(x: 315, y: 150))
arrow.move(to: NSPoint(x: 301, y: 164))
arrow.line(to: NSPoint(x: 315, y: 150))
arrow.line(to: NSPoint(x: 301, y: 136))
NSColor(calibratedWhite: 0.55, alpha: 1).setStroke()
arrow.stroke()
NSGraphicsContext.restoreGraphicsState()
try representation.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
