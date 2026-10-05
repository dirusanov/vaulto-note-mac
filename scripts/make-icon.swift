// Builds the macOS app icon (Resources/AppIcon-1024.png) from the mobile app's glyph:
// Apple's icon grid — an 824 pt rounded square inside a 1024 canvas with a soft
// shadow. A full-bleed square would be shown in a grey placeholder by macOS.
import AppKit

let args = CommandLine.arguments
let glyphURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])

let size = 1024.0
let inset = 100.0
let tile = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let radius = tile.width * 0.2237

guard let glyph = NSImage(contentsOf: glyphURL),
      let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let path = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor.white.setFill()
path.fill()
NSGraphicsContext.restoreGraphicsState()

// Subtle top-to-bottom sheen so the tile doesn't look flat next to system icons.
NSGradient(starting: NSColor(white: 1, alpha: 1), ending: NSColor(white: 0.93, alpha: 1))?.draw(in: path, angle: -90)

NSGraphicsContext.saveGraphicsState()
path.addClip()
// The glyph PNG already has generous padding; scale it to fill the tile.
glyph.draw(in: tile.insetBy(dx: -40, dy: -40), from: .zero, operation: .multiply, fraction: 1)
NSGraphicsContext.restoreGraphicsState()

NSColor.black.withAlphaComponent(0.08).setStroke()
path.lineWidth = 2
path.stroke()
NSGraphicsContext.restoreGraphicsState()

try rep.representation(using: .png, properties: [:])!.write(to: outURL)
