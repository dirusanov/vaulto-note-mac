import XCTest
@testable import VaultoNote

/// End-to-end check of audio loading + whisper.cpp on the real model. Skipped when the
/// model hasn't been downloaded on this Mac.
final class TranscriptionTests: XCTestCase {
    private static let engine = WhisperEngine()

    override class func tearDown() {
        // ggml's Metal backend asserts at exit if a context is still alive.
        engine.unloadSync()
        super.tearDown()
    }

    private func speak(_ text: String, voice: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vaulto-\(voice).aiff")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", voice, "-o", url.path, text]
        try say.run()
        say.waitUntilExit()
        return url
    }

    private func transcribe(_ text: String, voice: String, language: String = "auto", prompt: String = "") throws -> Transcript {
        let model = WhisperModel.defaultModel
        try XCTSkipUnless(model.isDownloaded, "model not downloaded")
        try Self.engine.loadSync(modelPath: model.fileURL.path)
        let samples = try AudioFileLoader.load(url: try speak(text, voice: voice))
        return try Self.engine.transcribeSync(samples: samples, language: language, prompt: prompt)
    }

    func testRussianWithAutoDetect() throws {
        let result = try transcribe("Встреча в пятницу в три часа.", voice: "Milena")
        XCTAssertEqual(result.language, "ru")
        XCTAssertTrue(result.text.lowercased().contains("пятниц"), result.text)
    }

    func testEnglishWithAutoDetect() throws {
        let result = try transcribe("Remind me to buy coffee tomorrow.", voice: "Samantha")
        XCTAssertEqual(result.language, "en")
        XCTAssertTrue(result.text.lowercased().contains("coffee"), result.text)
    }

    func testVeryShortClipIsPaddedNotRejected() throws {
        let result = try transcribe("Да.", voice: "Milena", language: "ru")
        XCTAssertLessThan(result.audioSeconds, 1.5)
        XCTAssertFalse(result.text.isEmpty)
    }

    func testFastEnoughForDictation() throws {
        let result = try transcribe("Нужно задеплоить новый билд на продакшн и проверить синхронизацию заметок.", voice: "Milena")
        XCTAssertLessThan(result.elapsedSeconds, 3, "took \(result.elapsedSeconds)s for \(result.audioSeconds)s of audio")
    }
}
