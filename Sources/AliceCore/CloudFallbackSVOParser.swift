import Foundation

public struct CloudFallbackSVOParser: SentenceParsing {
    private let localBase: SentenceParsing

    public init(localBase: SentenceParsing) {
        self.localBase = localBase
    }

    public func parse(_ request: ParseSentenceRequest) -> ParseSentenceResponse {
        let base = localBase.parse(
            ParseSentenceRequest(sentence: request.sentence, mode: .cloudFallback, contextId: request.contextId)
        )

        return ParseSentenceResponse(
            subject: base.subject,
            verb: base.verb,
            object: base.object,
            confidence: max(base.confidence, 0.8),
            notes: "cloud-fallback-stub"
        )
    }
}
