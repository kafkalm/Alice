import Foundation
import NaturalLanguage

public struct NLTokenizerSentenceSplitter: SentenceSplitting {
    public init() {}

    public func split(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = trimmed

        var sentences: [String] = []
        let start = trimmed.startIndex
        let end = trimmed.endIndex
        tokenizer.enumerateTokens(in: start..<end) { range, _ in
            let sentence = String(trimmed[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }

        if sentences.isEmpty {
            return [trimmed]
        }
        return sentences
    }
}
