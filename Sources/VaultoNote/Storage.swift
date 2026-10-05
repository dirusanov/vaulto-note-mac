import Foundation

enum AppPaths {
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("VaultoNote", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let models: URL = {
        let dir = support.appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let history = support.appendingPathComponent("history.json")
}

struct DictationLanguage {
    let code: String
    private let name: String

    var title: String { code == "auto" ? L10n.t("lang.auto") : name }

    static let all: [DictationLanguage] = [
        .init(code: "auto", name: ""),
        .init(code: "ru", name: "Русский"),
        .init(code: "en", name: "English"),
        .init(code: "de", name: "Deutsch"),
        .init(code: "uk", name: "Українська"),
        .init(code: "es", name: "Español"),
        .init(code: "fr", name: "Français"),
        .init(code: "pt", name: "Português"),
        .init(code: "zh", name: "中文"),
        .init(code: "ja", name: "日本語"),
    ]
}

enum Settings {
    private static let defaults = UserDefaults.standard

    /// "system" or an `L10n.languages` code. Also written to AppleLanguages so the
    /// system-drawn parts (About panel, permission prompts) match after a relaunch.
    static var interfaceLanguage: String {
        get { defaults.string(forKey: "interfaceLanguage") ?? "system" }
        set {
            defaults.set(newValue, forKey: "interfaceLanguage")
            if newValue == "system" {
                defaults.removeObject(forKey: "AppleLanguages")
            } else {
                defaults.set([newValue], forKey: "AppleLanguages")
            }
        }
    }

    static var language: String {
        get { defaults.string(forKey: "language") ?? "auto" }
        set { defaults.set(newValue, forKey: "language") }
    }

    static var triggerKey: TriggerKey {
        get { defaults.string(forKey: "triggerKey").flatMap(TriggerKey.init) ?? .rightOption }
        set { defaults.set(newValue.rawValue, forKey: "triggerKey") }
    }

    static var modelID: String {
        get { defaults.string(forKey: "modelID") ?? WhisperModel.defaultModel.id }
        set { defaults.set(newValue, forKey: "modelID") }
    }

    static var showInDock: Bool {
        get { defaults.object(forKey: "showInDock") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showInDock") }
    }

    static var trailingSpace: Bool {
        get { defaults.object(forKey: "trailingSpace") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "trailingSpace") }
    }
}

struct HistoryEntry: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let text: String
    let language: String
    let audioSeconds: Double
}

/// Local dictation history. Stays on this Mac; nothing is synced yet.
final class HistoryStore {
    private static let limit = 500
    private(set) var entries: [HistoryEntry] = []

    init() {
        if let data = try? Data(contentsOf: AppPaths.history) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
        }
    }

    func add(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: AppPaths.history, options: .atomic)
    }
}
