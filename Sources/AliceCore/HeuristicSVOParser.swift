import Foundation
import NaturalLanguage

public struct HeuristicSVOParser: SentenceParsing {
    private struct TaggedToken {
        let text: String
        let tag: NLTag?
    }

    private let temporalWords: Set<String> = [
        "today", "tomorrow", "yesterday", "tonight", "morning", "afternoon", "evening", "week", "month", "year"
    ]

    public init() {}

    public func parse(_ request: ParseSentenceRequest) -> ParseSentenceResponse {
        let tokens = tagTokens(sentence: request.sentence)
        guard !tokens.isEmpty else {
            return ParseSentenceResponse(subject: "", verb: "", object: "", confidence: 0.0, notes: "empty-sentence")
        }

        let verbIndex = tokens.firstIndex(where: { $0.tag == .verb })
        let subjectIndex = findSubjectIndex(tokens: tokens, verbIndex: verbIndex)
        let objectIndex = findObjectIndex(tokens: tokens, verbIndex: verbIndex)

        let subject = subjectIndex.map { tokens[$0].text } ?? ""
        let verb = verbIndex.map { tokens[$0].text } ?? ""
        let object = objectIndex.map { tokens[$0].text } ?? ""

        var confidence = 0.2
        confidence += subject.isEmpty ? 0.0 : 0.3
        confidence += verb.isEmpty ? 0.0 : 0.3
        confidence += object.isEmpty ? 0.0 : 0.2

        if verbIndex == nil {
            confidence = min(confidence, 0.45)
        }

        confidence = max(0.0, min(confidence, 0.99))
        let note = confidence < 0.6 ? "low-confidence-local-heuristic" : nil

        return ParseSentenceResponse(
            subject: subject,
            verb: verb,
            object: object,
            confidence: confidence,
            notes: note
        )
    }

    private func findSubjectIndex(tokens: [TaggedToken], verbIndex: Int?) -> Int? {
        let searchRange: Range<Int>
        if let verbIndex {
            searchRange = 0..<verbIndex
        } else {
            searchRange = 0..<tokens.count
        }

        for index in searchRange.reversed() {
            if isEntityLike(tokens[index].tag) {
                return index
            }
        }
        return nil
    }

    private func findObjectIndex(tokens: [TaggedToken], verbIndex: Int?) -> Int? {
        guard let verbIndex else { return nil }
        guard verbIndex + 1 < tokens.count else { return nil }

        for index in (verbIndex + 1)..<tokens.count {
            let token = tokens[index]
            if isEntityLike(token.tag), !temporalWords.contains(token.text.lowercased()) {
                return index
            }
        }
        return nil
    }

    private func isEntityLike(_ tag: NLTag?) -> Bool {
        tag == .noun || tag == .pronoun || tag == .personalName || tag == .organizationName || tag == .placeName
    }

    private func tagTokens(sentence: String) -> [TaggedToken] {
        var taggedTokens: [TaggedToken] = []
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = sentence

        let range = sentence.startIndex..<sentence.endIndex
        tagger.enumerateTags(
            in: range,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitPunctuation, .omitWhitespace]
        ) { tag, tokenRange in
            let token = String(sentence[tokenRange])
            taggedTokens.append(TaggedToken(text: token, tag: tag))
            return true
        }

        return taggedTokens
    }
}
