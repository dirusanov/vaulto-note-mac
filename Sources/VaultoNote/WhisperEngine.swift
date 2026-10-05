import Foundation
import whisper

struct Transcript {
    let text: String
    let language: String
    let audioSeconds: Double
    let elapsedSeconds: Double
}

enum WhisperError: LocalizedError {
    case modelNotLoaded
    case loadFailed(String)
    case transcriptionFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return L10n.t("error.model_not_loaded")
        case .loadFailed(let path): return L10n.t("error.load_failed", path)
        case .transcriptionFailed(let code): return L10n.t("error.transcription_failed", Int(code))
        }
    }
}

/// Thin wrapper over whisper.cpp. All calls are serialized on one queue because a
/// whisper_context is not thread-safe.
final class WhisperEngine {
    static let sampleRate = 16_000

    private let queue = DispatchQueue(label: "vaulto.whisper", qos: .userInitiated)
    private var ctx: OpaquePointer?
    private(set) var loadedModelPath: String?

    deinit {
        unloadSync()
    }

    /// Must run before the process exits: ggml's Metal backend asserts in its static
    /// destructor if a context is still alive.
    func unloadSync() {
        if let ctx { whisper_free(ctx) }
        ctx = nil
        loadedModelPath = nil
    }

    func unload() {
        queue.sync { unloadSync() }
    }

    func load(modelPath: String, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            let result = Result { try self.loadSync(modelPath: modelPath) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func loadSync(modelPath: String) throws {
        if loadedModelPath == modelPath, ctx != nil { return }
        unloadSync()

        var cparams = whisper_context_default_params()
        cparams.use_gpu = true
        cparams.flash_attn = true
        guard let newCtx = whisper_init_from_file_with_params(modelPath, cparams) else {
            throw WhisperError.loadFailed(modelPath)
        }
        ctx = newCtx
        loadedModelPath = modelPath
    }

    func transcribe(
        samples: [Float],
        language: String,
        completion: @escaping (Result<Transcript, Error>) -> Void
    ) {
        queue.async {
            let result = Result { try self.transcribeSync(samples: samples, language: language) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// `language` is a Whisper code ("ru", "en", …) or "auto" for per-utterance detection.
    func transcribeSync(samples input: [Float], language: String) throws -> Transcript {
        guard let ctx else { throw WhisperError.modelNotLoaded }
        let started = Date()

        // whisper.cpp refuses clips shorter than one second; pad with silence.
        var samples = input
        let minSamples = Self.sampleRate + Self.sampleRate / 10
        if samples.count < minSamples {
            samples.append(contentsOf: [Float](repeating: 0, count: minSamples - samples.count))
        }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = Int32(max(1, min(8, ProcessInfo.processInfo.activeProcessorCount - 2)))
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        params.no_context = true
        params.no_timestamps = true
        params.suppress_nst = true

        let languagePtr = strdup(language)
        defer { free(languagePtr) }
        params.language = UnsafePointer(languagePtr)
        params.detect_language = false

        let code = samples.withUnsafeBufferPointer { buffer in
            whisper_full(ctx, params, buffer.baseAddress, Int32(buffer.count))
        }
        guard code == 0 else { throw WhisperError.transcriptionFailed(code) }

        var text = ""
        for i in 0..<whisper_full_n_segments(ctx) {
            if let segment = whisper_full_get_segment_text(ctx, i) {
                text += String(cString: segment)
            }
        }
        let langID = whisper_full_lang_id(ctx)
        let detected = langID >= 0 ? String(cString: whisper_lang_str(langID)) : language

        return Transcript(
            text: TextCleanup.clean(text),
            language: detected,
            audioSeconds: Double(input.count) / Double(Self.sampleRate),
            elapsedSeconds: Date().timeIntervalSince(started)
        )
    }
}
