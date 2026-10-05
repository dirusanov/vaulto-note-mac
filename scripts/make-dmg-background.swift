// Draws the DMG window background (660×420 pt) at 1x and 2x:
//   swift scripts/make-dmg-background.swift <out-1x.png> <out-2x.png>
// Icons sit at (170, 190) and (490, 190) — keep in sync with scripts/dmg-settings.py.
import AppKit

let width = 660.0, height = 420.0

func draw(scale: CGFloat, to path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Same soft blue gradient as the README banner.
    NSGradient(starting: NSColor(srgbRed: 0.93, green: 0.95, blue: 1, alpha: 1),
               ending: NSColor(srgbRed: 0.985, green: 0.985, blue: 1, alpha: 1))!
        .draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -45)

    // Arrow between the two icons (AppKit's origin is bottom-left; icons are at y=190 from the top).
    let y = height - 190
    let blue = NSColor(srgbRed: 0, green: 0.4, blue: 1, alpha: 0.85)
    blue.setStroke()
    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: 268, y: y))
    shaft.line(to: NSPoint(x: 384, y: y))
    shaft.lineWidth = 4
    shaft.lineCapStyle = .round
    let dash: [CGFloat] = [2, 10]
    shaft.setLineDash(dash, count: 2, phase: 0)
    shaft.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 376, y: y + 12))
    head.line(to: NSPoint(x: 394, y: y))
    head.line(to: NSPoint(x: 376, y: y - 12))
    head.lineWidth = 4
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        NSAttributedString(string: string, attributes: attributes)
            .draw(in: NSRect(x: 20, y: y, width: width - 40, height: size * 1.6))
    }
    text("Drag Vaulto Note to Applications", size: 20, weight: .semibold,
         color: NSColor(white: 0.12, alpha: 1), y: 84)
    text("First launch: right-click the app → Open", size: 13, weight: .regular,
         color: NSColor(white: 0.42, alpha: 1), y: 52)

    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

draw(scale: 1, to: CommandLine.arguments[1])
draw(scale: 2, to: CommandLine.arguments[2])
