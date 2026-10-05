import AppKit

// `VaultoNote --transcribe <audio file> [language]` runs the engine headless; used to
// check model quality and speed without the menu bar UI.
if let flag = CommandLine.arguments.firstIndex(of: "--transcribe"), CommandLine.arguments.count > flag + 1 {
    let args = CommandLine.arguments
    let file = URL(fileURLWithPath: args[flag + 1])
    let language = args.count > flag + 2 ? args[flag + 2] : "auto"
    let model = WhisperModel.find(Settings.modelID)
    do {
        let engine = WhisperEngine()
        let loadStart = Date()
        try engine.loadSync(modelPath: model.fileURL.path)
        let loadSeconds = Date().timeIntervalSince(loadStart)
        let samples = try AudioFileLoader.load(url: file)
        let transcript = try engine.transcribeSync(samples: samples, language: language)
        engine.unloadSync()
        print(transcript.text)
        let stats = String(
            format: "[%@] model=%@ load=%.2fs audio=%.1fs transcribe=%.2fs",
            transcript.language, model.id, loadSeconds, transcript.audioSeconds, transcript.elapsedSeconds
        )
        FileHandle.standardError.write((stats + "\n").data(using: .utf8)!)
        exit(0)
    } catch {
        FileHandle.standardError.write("\(error.localizedDescription)\n".data(using: .utf8)!)
        exit(1)
    }
}

if let flag = CommandLine.arguments.firstIndex(of: "--banner"), CommandLine.arguments.count > flag + 2 {
    Snapshot.banner(to: URL(fileURLWithPath: CommandLine.arguments[flag + 1]),
                    screenshot: URL(fileURLWithPath: CommandLine.arguments[flag + 2]))
    exit(0)
}

if let flag = CommandLine.arguments.firstIndex(of: "--demo"), CommandLine.arguments.count > flag + 1 {
    Snapshot.demo(directory: URL(fileURLWithPath: CommandLine.arguments[flag + 1]))
    exit(0)
}

if let flag = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > flag + 1 {
    let args = Array(CommandLine.arguments.dropFirst(flag + 1))
    let languages = args.count > 1 ? Array(args.dropFirst()) : ["ru", "en"]
    Snapshot.run(directory: URL(fileURLWithPath: args[0]), languages: languages)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(Settings.showInDock ? .regular : .accessory)
app.run()
