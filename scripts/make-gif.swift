// Assembles PNG frames into an animated GIF.
//   swift scripts/make-gif.swift <frames dir> <list.txt> <out.gif> [width]
// list.txt has one "file delay-seconds" pair per line.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let dir = URL(fileURLWithPath: args[1])
let lines = try String(contentsOf: URL(fileURLWithPath: args[2]), encoding: .utf8)
    .split(separator: "\n").map { $0.split(separator: " ") }
let width = args.count > 4 ? Int(args[4])! : 0

guard let destination = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: args[3]) as CFURL, UTType.gif.identifier as CFString, lines.count, nil
) else { exit(1) }
CGImageDestinationSetProperties(destination, [
    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
] as CFDictionary)

for line in lines {
    guard let image = NSImage(contentsOf: dir.appendingPathComponent(String(line[0]))),
          var cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
    if width > 0, cg.width > width {
        let height = cg.height * width / cg.width
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .high
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        cg = context.makeImage()!
    }
    CGImageDestinationAddImage(destination, cg, [
        kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: Double(line[1])!],
    ] as CFDictionary)
}
CGImageDestinationFinalize(destination)
