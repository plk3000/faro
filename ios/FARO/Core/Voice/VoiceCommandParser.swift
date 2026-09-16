import Foundation

struct VoiceCommandParser: Sendable {
    func parse(
        _ transcript: String,
        language: SupportedLanguage
    ) -> VoiceCommand? {
        var tokens = VoiceTextNormalizer.tokens(
            from: transcript,
            language: language
        )
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
            patterns: stopNavigatingPatterns(for: language)
        ) {
            return .stopNavigating
        }
        if matches(
            normalized,
            patterns: startNavigatingPatterns(for: language)
        ) {
            return .startNavigating
        }
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
        from tokens: [VoiceToken],
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

    private func removeLeadingFillers(
        from tokens: [VoiceToken],
        language: SupportedLanguage
    ) -> [VoiceToken] {
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
        from tokens: [VoiceToken],
        language: SupportedLanguage
    ) -> [VoiceToken] {
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
                ["hola", "faro"],
                ["faro"],
                ["please"],
                ["can", "you"],
                ["could", "you"],
                ["tell", "me"]
            ]
        case .spanishMexico:
            [
                ["hola", "faro"],
                ["hey", "faro"],
                ["ey", "faro"],
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

    private func startNavigatingPatterns(
        for language: SupportedLanguage
    ) -> [[String]] {
        switch language {
        case .englishUS:
            [
                ["start", "navigation"],
                ["start", "navigating"],
                ["begin", "navigation"]
            ]
        case .spanishMexico:
            [
                ["inicia", "navegacion"],
                ["iniciar", "navegacion"],
                ["empieza", "a", "navegar"],
                ["comienza", "la", "navegacion"]
            ]
        }
    }

    private func stopNavigatingPatterns(
        for language: SupportedLanguage
    ) -> [[String]] {
        switch language {
        case .englishUS:
            [
                ["stop", "navigation"],
                ["stop", "navigating"],
                ["end", "navigation"]
            ]
        case .spanishMexico:
            [
                ["deten", "navegacion"],
                ["detener", "navegacion"],
                ["para", "la", "navegacion"],
                ["deja", "de", "navegar"]
            ]
        }
    }
}
