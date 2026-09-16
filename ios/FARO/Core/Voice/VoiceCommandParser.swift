import Foundation

struct VoiceCommandParser: Sendable {
    private struct Token {
        let original: String
        let normalized: String
    }

    func parse(
        _ transcript: String,
        language: SupportedLanguage
    ) -> VoiceCommand? {
        var tokens = tokenize(transcript, language: language)
        tokens = removeLeadingFillers(from: tokens, language: language)
        tokens = removeTrailingFillers(from: tokens, language: language)
        guard !tokens.isEmpty else {
            return nil
        }

        if let command = rememberCommand(
            from: tokens,
            language: language
        ) {
            return command
        }

        let normalized = tokens.map(\.normalized)
        if matches(
            normalized,
            patterns: aheadPatterns(for: language)
        ) {
            return .whatIsAhead
        }
        if matches(
            normalized,
            patterns: locationPatterns(for: language)
        ) {
            return .whereAmI
        }
        if matches(
            normalized,
            patterns: describePatterns(for: language)
        ) {
            return .describeScene
        }
        return nil
    }

    private func rememberCommand(
        from tokens: [Token],
        language: SupportedLanguage
    ) -> VoiceCommand? {
        let normalized = tokens.map(\.normalized)
        for prefix in rememberPrefixes(for: language)
            where normalized.starts(with: prefix) {
            let label = tokens
                .dropFirst(prefix.count)
                .map(\.original)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !label.isEmpty {
                return .rememberPlace(label: label)
            }
        }
        return nil
    }

    private func tokenize(
        _ transcript: String,
        language: SupportedLanguage
    ) -> [Token] {
        transcript
            .split(whereSeparator: \.isWhitespace)
            .compactMap { substring in
                let original = String(substring).trimmingCharacters(
                    in: .punctuationCharacters.union(.symbols)
                )
                guard !original.isEmpty else {
                    return nil
                }
                let folded = original.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: language.locale
                )
                let scalars = folded.unicodeScalars.filter {
                    !CharacterSet.punctuationCharacters.contains($0)
                        && !CharacterSet.symbols.contains($0)
                }
                let normalized = String(
                    String.UnicodeScalarView(scalars)
                ).lowercased(with: language.locale)
                guard !normalized.isEmpty else {
                    return nil
                }
                return Token(
                    original: original,
                    normalized: normalized
                )
            }
    }

    private func removeLeadingFillers(
        from tokens: [Token],
        language: SupportedLanguage
    ) -> [Token] {
        var result = tokens
        var removed = true
        while removed {
            removed = false
            for filler in leadingFillers(for: language) {
                if result.map(\.normalized).starts(with: filler) {
                    result.removeFirst(filler.count)
                    removed = true
                    break
                }
            }
        }
        return result
    }

    private func removeTrailingFillers(
        from tokens: [Token],
        language: SupportedLanguage
    ) -> [Token] {
        var result = tokens
        var removed = true
        while removed {
            removed = false
            let normalized = result.map(\.normalized)
            for filler in trailingFillers(for: language)
                where normalized.count >= filler.count
                    && Array(normalized.suffix(filler.count)) == filler {
                result.removeLast(filler.count)
                removed = true
                break
            }
        }
        return result
    }

    private func matches(
        _ tokens: [String],
        patterns: [[String]]
    ) -> Bool {
        patterns.contains(tokens)
    }

    private func leadingFillers(
        for language: SupportedLanguage
    ) -> [[String]] {
        switch language {
        case .englishUS:
            [
                ["hey", "faro"],
                ["faro"],
                ["please"],
                ["can", "you"],
                ["could", "you"],
                ["tell", "me"]
            ]
        case .spanishMexico:
            [
                ["oye", "faro"],
                ["faro"],
                ["por", "favor"],
                ["puedes"],
                ["podrias"],
                ["dime"]
            ]
        }
    }

    private func trailingFillers(
        for language: SupportedLanguage
    ) -> [[String]] {
        switch language {
        case .englishUS:
            [["please"]]
        case .spanishMexico:
            [["por", "favor"]]
        }
    }

    private func describePatterns(
        for language: SupportedLanguage
    ) -> [[String]] {
        switch language {
        case .englishUS:
            [
                ["describe"],
                ["describe", "scene"],
                ["describe", "the", "scene"]
            ]
        case .spanishMexico:
            [
                ["describe"],
                ["describe", "la", "escena"]
            ]
        }
    }

    private func locationPatterns(
        for language: SupportedLanguage
    ) -> [[String]] {
        switch language {
        case .englishUS:
            [
                ["where", "am", "i"],
                ["where", "i", "am"]
            ]
        case .spanishMexico:
            [
                ["donde", "estoy"],
                ["en", "donde", "estoy"]
            ]
        }
    }

    private func aheadPatterns(
        for language: SupportedLanguage
    ) -> [[String]] {
        switch language {
        case .englishUS:
            [
                ["what", "is", "ahead"],
                ["whats", "ahead"],
                ["what", "is", "in", "front", "of", "me"],
                ["describe", "what", "is", "ahead"]
            ]
        case .spanishMexico:
            [
                ["que", "hay", "delante"],
                ["que", "hay", "enfrente"],
                ["que", "hay", "frente", "a", "mi"],
                ["describe", "que", "hay", "delante"]
            ]
        }
    }

    private func rememberPrefixes(
        for language: SupportedLanguage
    ) -> [[String]] {
        switch language {
        case .englishUS:
            [
                ["remember", "this", "place", "as"],
                ["remember", "this", "location", "as"],
                ["remember", "this", "as"]
            ]
        case .spanishMexico:
            [
                ["recuerda", "este", "lugar", "como"],
                ["recuerda", "esta", "ubicacion", "como"],
                ["recuerda", "esto", "como"]
            ]
        }
    }
}
