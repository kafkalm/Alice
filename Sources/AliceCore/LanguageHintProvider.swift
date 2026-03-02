import Foundation
import NaturalLanguage

public struct NaturalLanguageHintProvider: LanguageHintProviding {
    public init() {}

    public func detectLanguageHint(for text: String) -> LanguageHint {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unknown }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)

        if recognizer.dominantLanguage == .english {
            return .en
        }

        return .unknown
    }
}
