import Foundation

/// Port of vaulto_note_mobile/src/utils/whisperText.ts.
///
/// Whisper was trained on subtitled video, so on silence or noise it tends to
/// "hear" the credits and sign-offs of those subtitles. These lines are dropped
/// from transcripts; real speech that only contains them is rare.
enum TextCleanup {
    private static let patterns: [NSRegularExpression] = [
        ("продолжение следует\\.*", true),
        ("субтитр\\S*\\s+(?:сделал|создавал|делал|подготовил)\\S*\\s+\\S+", true),
        ("редактор субтитров[^.!?]*[.!?]?", true),
        ("корректор\\s+[А-ЯЁA-Z]\\.\\s*\\S+", false),
        ("спасибо за (?:просмотр|внимание)[.!]*", true),
        ("подписывайтесь на (?:канал|наш канал)[^.!?]*[.!?]?", true),
        ("thanks? (?:you )?for watching[.!]*", true),
        ("subtitles? by [^.!?]*[.!?]?", true),
        ("(?:please )?subscribe to (?:my|our|the) channel[.!]*", true),
        ("\\[(?:music|музыка|silence|тишина|blank_audio)\\]", true),
        // Sound captions Whisper adds on non-speech: "[Birds chirping]", "[Смех]", "(звук двигателя)".
        ("^\\s*[\\[(][^\\])\\n]{1,40}[\\])]\\s*$", false),
        ("\\((?:music|музыка)\\)", true),
    ].map { pattern, caseInsensitive in
        var options: NSRegularExpression.Options = [.anchorsMatchLines]
        if caseInsensitive { options.insert(.caseInsensitive) }
        return try! NSRegularExpression(pattern: pattern, options: options)
    }

    static func clean(_ text: String) -> String {
        var result = text
        for pattern in patterns {
            let range = NSRange(result.startIndex..., in: result)
            result = pattern.stringByReplacingMatches(in: result, range: range, withTemplate: " ")
        }
        result = result.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\s+([.,!?])", with: "$1", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
