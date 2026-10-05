import AppKit
import SwiftUI

/// `VaultoNote --snapshot <dir> [lang …]` renders every page of the main window in
/// light and dark appearance to PNG files, with sample data. Used to review layout
/// (wrapping, truncation, alignment) without clicking through the app.
enum Snapshot {
    static func run(directory: URL, languages: [String]) {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for language in languages {
            L10n.override = language
            for (appearanceName, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                for setupDone in [true, false] {
                    let app = AppController()
                    app.applyPreviewState(setupDone: setupDone)
                    let pages: [Page] = setupDone ? Page.allCases : [.home]
                    for page in pages {
                        app.page = page
                        let name = "\(language)-\(appearanceName)-\(page.rawValue)\(setupDone ? "" : "-setup").png"
                        render(RootView(app: app), size: NSSize(width: 920, height: 640),
                               appearance: appearance, to: directory.appendingPathComponent(name))
                    }
                }
                let hud = HUDModel()
                hud.state = .recording(started: Date().addingTimeInterval(-7))
                hud.levels = (0..<24).map { i in Float(0.25 + 0.6 * abs(sin(Double(i) / 2.5))) }
                render(HUDView(model: hud), size: NSSize(width: 360, height: 72), appearance: appearance,
                       to: directory.appendingPathComponent("\(language)-\(appearanceName)-hud.png"))
            }
        }
    }

    private static func render<V: View>(_ view: V, size: NSSize, appearance: NSAppearance.Name, to url: URL) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.contentViewController = NSHostingController(rootView: view)
        window.setContentSize(size)
        window.orderFrontRegardless()
        window.alphaValue = 0.01
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        guard let frameView = window.contentView?.superview,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
    }
}
