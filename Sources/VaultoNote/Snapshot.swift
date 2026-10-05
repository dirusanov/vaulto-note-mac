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
                        if page == .general {
                            render(RootView(app: app), size: NSSize(width: 920, height: 1200),
                                   appearance: appearance,
                                   to: directory.appendingPathComponent("\(language)-\(appearanceName)-general-full.png"))
                        }
                    }
                }
                for (suffix, recording, result) in [("recording", true, nil as String?),
                                                     ("result", false, "Купить молоко, хлеб и кофе. Позвонить маме вечером.")] {
                    let app = AppController()
                    app.applyPreviewState(setupDone: true)
                    app.applyPreviewDictation(recording: recording, result: result)
                    render(RootView(app: app), size: NSSize(width: 920, height: 640), appearance: appearance,
                           to: directory.appendingPathComponent("\(language)-\(appearanceName)-home-\(suffix).png"))
                }
                let fresh = AppController()
                fresh.applyPreviewState(setupDone: false)
                for step in OnboardingStep.allCases {
                    render(OnboardingView(app: fresh, step: step) {}, size: NSSize(width: 600, height: 560),
                           appearance: appearance,
                           to: directory.appendingPathComponent("\(language)-\(appearanceName)-onboarding-\(step.rawValue).png"))
                }
                let practiceStates: [(String, AppController.ModelState, String?)] = [
                    ("preparing", .loading, nil),
                    ("ready", .ready, nil),
                    ("download-error", .notLoaded, L10n.t("model.download_error", "HTTP 503")),
                    ("load-error", .failed(L10n.t("error.load_failed", "Whisper")), nil),
                ]
                for (name, state, downloadError) in practiceStates {
                    let app = AppController()
                    app.applyPreviewState(setupDone: false)
                    app.applyPreviewModelState(state, downloadError: downloadError)
                    render(OnboardingView(app: app, step: .practice) {}, size: NSSize(width: 600, height: 560),
                           appearance: appearance,
                           to: directory.appendingPathComponent("\(language)-\(appearanceName)-onboarding-practice-\(name).png"))
                }
                let hud = HUDModel()
                hud.state = .recording(started: Date().addingTimeInterval(-7))
                hud.levels = (0..<24).map { i in Float(0.25 + 0.6 * abs(sin(Double(i) / 2.5))) }
                render(HUDView(model: hud), size: NSSize(width: 460, height: 80), appearance: appearance,
                       to: directory.appendingPathComponent("\(language)-\(appearanceName)-hud.png"))
            }
        }
    }

    /// `--demo <dir>`: numbered frames for the README GIFs, with `frames.txt` listing
    /// "file delay" pairs for scripts/make-gif.swift.
    static func demo(directory: URL) {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        L10n.override = "en"
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var flow: [String] = []
        var index = 0
        func frame(_ app: AppController, delay: Double) {
            let name = String(format: "flow-%03d.png", index)
            index += 1
            render(RootView(app: app), size: NSSize(width: 920, height: 640), appearance: .aqua,
                   to: directory.appendingPathComponent(name))
            flow.append("\(name) \(delay)")
        }
        let app = AppController()
        app.applyPreviewState(setupDone: true)
        app.applyPreviewDictation(recording: false, result: nil)
        frame(app, delay: 1.4)
        for i in 0..<18 {
            let level = Float(0.25 + 0.55 * abs(sin(Double(i) * 0.9)))
            app.applyPreviewDictation(recording: true, result: nil, elapsed: Double(i) * 0.25, level: level)
            frame(app, delay: 0.12)
        }
        app.applyPreviewDictation(recording: false, result: nil, transcribing: true)
        frame(app, delay: 0.7)
        app.applyPreviewDictation(recording: false, result: "Ship the new build on Friday and send the release notes to the team.")
        frame(app, delay: 3.0)
        try? flow.joined(separator: "\n").write(to: directory.appendingPathComponent("flow.txt"), atomically: true, encoding: .utf8)

        var hud: [String] = []
        let model = HUDModel()
        let started = Date().addingTimeInterval(-3)
        model.state = .recording(started: started)
        for i in 0..<40 {
            model.levels.removeFirst()
            model.levels.append(Float(0.15 + 0.7 * abs(sin(Double(i) * 0.55) * cos(Double(i) * 0.21))))
            let name = String(format: "hud-%03d.png", i)
            render(HUDView(model: model), size: NSSize(width: 460, height: 80), appearance: .darkAqua,
                   to: directory.appendingPathComponent(name), contentOnly: true)
            hud.append("\(name) 0.07")
        }
        try? hud.joined(separator: "\n").write(to: directory.appendingPathComponent("hud.txt"), atomically: true, encoding: .utf8)
    }

    /// `--banner <file> <screenshot>`: 1280×640 social preview / README header.
    static func banner(to url: URL, screenshot: URL) {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let shot = NSImage(contentsOf: screenshot) ?? NSImage()
        let view = ZStack {
            LinearGradient(colors: [Color(red: 0.93, green: 0.95, blue: 1), Color(red: 0.98, green: 0.98, blue: 1)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 40) {
                VStack(alignment: .leading, spacing: 18) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
                    Text("Vaulto Note").font(.system(size: 56, weight: .bold))
                    Text("Hold a key. Speak. Text appears.")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color(red: 0, green: 0.4, blue: 1))
                    Text("Free, offline Whisper dictation for Mac.\nPrivate — audio never leaves your computer.")
                        .font(.system(size: 19))
                        .foregroundStyle(Color(white: 0.35))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 470, alignment: .leading)
                Image(nsImage: shot)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 640)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.2), radius: 24, y: 10)
            }
            .padding(.horizontal, 60)
        }
        .foregroundStyle(Color(white: 0.1))
        render(view, size: NSSize(width: 1280, height: 640), appearance: .aqua, to: url, contentOnly: true)
    }

    private static func render<V: View>(_ view: V, size: NSSize, appearance: NSAppearance.Name, to url: URL,
                                        contentOnly: Bool = false) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: contentOnly ? [.borderless] : [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        if contentOnly {
            window.isOpaque = false
            window.backgroundColor = .clear
        }
        let host = NSHostingController(rootView: view)
        if contentOnly {
            host.view.wantsLayer = true
            host.view.layer?.backgroundColor = .clear
        }
        window.contentViewController = host
        window.setContentSize(size)
        window.orderFrontRegardless()
        window.alphaValue = 0.01
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        guard let frameView = contentOnly ? window.contentView : window.contentView?.superview,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
    }
}
