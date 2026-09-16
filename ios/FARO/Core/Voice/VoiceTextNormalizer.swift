import Foundation

struct VoiceToken: Equatable, Sendable {
    let original: String
    let normalized: String
}

enum VoiceTextNormalizer {
    static func tokens(
        from text: String,
        language: SupportedLanguage
    ) -> [VoiceToken] {
        text
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
                return VoiceToken(
                    original: original,
                    normalized: normalized
                )
            }
    }
}
