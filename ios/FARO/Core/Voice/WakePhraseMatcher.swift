import Foundation

struct WakePhraseMatcher: Sendable {
    func matches(
        _ transcript: String,
        language: SupportedLanguage
    ) -> Bool {
        let tokens = VoiceTextNormalizer.tokens(
            from: transcript,
            language: language
        ).map(\.normalized)

        return acceptedPatterns.contains { pattern in
            guard tokens.count >= pattern.count else {
                return false
            }
            return tokens.indices.dropLast(pattern.count - 1).contains {
                index in
                Array(tokens[index..<(index + pattern.count)]) == pattern
            }
        }
    }

    private var acceptedPatterns: [[String]] {
        [
            ["hey", "faro"],
            ["ey", "faro"],
            ["hey", "farrow"],
            ["hey", "pharaoh"],
            ["hola", "faro"]
        ]
    }
}

struct WakePhraseTranscriptAccumulator: Sendable {
    private(set) var hasDetectedWakePhrase = false
    private var rollingTranscript = ""

    mutating func observe(
        _ fragment: String,
        language: SupportedLanguage,
        matcher: WakePhraseMatcher = WakePhraseMatcher()
    ) -> Bool {
        guard !hasDetectedWakePhrase, !fragment.isEmpty else {
            return false
        }
        rollingTranscript = String(
            "\(rollingTranscript) \(fragment)".suffix(200)
        )
        guard matcher.matches(
            rollingTranscript,
            language: language
        ) else {
            return false
        }
        hasDetectedWakePhrase = true
        return true
    }
}

extension SupportedLanguage {
    var wakePhraseContextualStrings: [String] {
        [
            "Hey FARO",
            "Hola FARO"
        ]
    }
}
