import AppKit
import XCTest
@testable import VaultoNote

final class TextCleanupTests: XCTestCase {
    func testDropsSubtitleHallucinations() {
        XCTAssertEqual(TextCleanup.clean("Продолжение следует..."), "")
        XCTAssertEqual(TextCleanup.clean("Thanks for watching!"), "")
        XCTAssertEqual(TextCleanup.clean("[Music]"), "")
        XCTAssertEqual(TextCleanup.clean("Субтитры сделал DimaTorzok"), "")
    }

    func testKeepsRealSpeech() {
        let text = "Привет! Нужно задеплоить новый билд."
        XCTAssertEqual(TextCleanup.clean("  \(text)  "), text)
    }

    func testTidiesSpacesBeforePunctuation() {
        XCTAssertEqual(TextCleanup.clean("Привет , мир !"), "Привет, мир!")
    }
}

final class ShortcutTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let shortcuts: [Shortcut] = [
            .modifier(.rightOption),
            .modifier(.fn),
            .combo(keyCode: 49, modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue),
        ]
        for shortcut in shortcuts {
            let data = try JSONEncoder().encode(shortcut)
            XCTAssertEqual(try JSONDecoder().decode(Shortcut.self, from: data), shortcut)
        }
    }

    func testComboKeycapsAreOrderedLikeMacMenus() {
        L10n.override = "en"
        defer { L10n.override = nil }
        let shortcut = Shortcut.combo(
            keyCode: 49,
            modifiers: NSEvent.ModifierFlags([.command, .shift, .option, .control]).rawValue
        )
        XCTAssertEqual(shortcut.keycaps, ["⌃", "⌥", "⇧", "⌘", "Space"])
    }

    func testInlineTitleReadsInsideSentences() {
        L10n.override = "ru"
        defer { L10n.override = nil }
        XCTAssertEqual(Shortcut.modifier(.rightOption).title, "Правый ⌥")
        XCTAssertEqual(Shortcut.modifier(.rightOption).inlineTitle, "правый ⌥")
    }
}

final class LocalizationTests: XCTestCase {
    func testEveryStringHasAllLanguagesAndMatchingPlaceholders() {
        XCTAssertEqual(L10n.audit(), [])
    }

    func testDynamicKeysExist() {
        for page in Page.allCases { XCTAssertTrue(L10n.has("page.\(page.rawValue)"), page.rawValue) }
        for mode in TriggerMode.allCases {
            XCTAssertTrue(L10n.has("mode.\(mode.rawValue).title"))
            XCTAssertTrue(L10n.has("mode.\(mode.rawValue).summary"))
        }
        for model in WhisperModel.all { XCTAssertTrue(L10n.has("model.summary.\(model.id)"), model.id) }
    }

    func testSizesUseLanguageDecimalSeparator() {
        L10n.override = "ru"
        XCTAssertEqual(L10n.size(gigabytes: 1.6), "1,6 ГБ")
        XCTAssertEqual(L10n.size(gigabytes: 0.574), "574 МБ")
        L10n.override = "en"
        XCTAssertEqual(L10n.size(gigabytes: 1.6), "1.6 GB")
        L10n.override = nil
    }
}
