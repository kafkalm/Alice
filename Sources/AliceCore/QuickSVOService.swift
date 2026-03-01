import Foundation

public final class QuickSVOService {
    private let sentenceSplitter: SentenceSplitting
    private let localParser: SentenceParsing
    private let cloudParser: SentenceParsing?
    private let eventLogger: EventLogging
    private let settings: QuickSVOSettings

    public init(
        sentenceSplitter: SentenceSplitting,
        localParser: SentenceParsing,
        cloudParser: SentenceParsing? = nil,
        eventLogger: EventLogging = NoopEventLogger(),
        settings: QuickSVOSettings = QuickSVOSettings()
    ) {
        self.sentenceSplitter = sentenceSplitter
        self.localParser = localParser
        self.cloudParser = cloudParser
        self.eventLogger = eventLogger
        self.settings = settings
    }

    public func parseParagraph(text: String, sourceApp: String) throws -> ParseParagraphResponse {
        let contextId = UUID().uuidString
        let start = Date()

        eventLogger.log(
            QuickSVOEvent(
                name: .triggered,
                contextId: contextId,
                timestamp: start.timeIntervalSince1970,
                metadata: ["source_app": sourceApp]
            )
        )

        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            eventLogger.log(
                QuickSVOEvent(
                    name: .failed,
                    contextId: contextId,
                    timestamp: Date().timeIntervalSince1970,
                    metadata: ["reason": "no_text_detected"]
                )
            )
            throw QuickSVOError.noTextDetected
        }

        var sentences = sentenceSplitter.split(normalizedText)
        if sentences.isEmpty {
            sentences = [normalizedText]
        }

        var fallbackUsed = false
        var parsedSentences: [ParseParagraphSentence] = []

        for (index, sentence) in sentences.enumerated() {
            let request = ParseSentenceRequest(sentence: sentence, mode: .local, contextId: "\(contextId)-\(index)")
            var result = localParser.parse(request)

            if shouldUseFallback(for: result), let cloudParser {
                result = cloudParser.parse(
                    ParseSentenceRequest(
                        sentence: sentence,
                        mode: .cloudFallback,
                        contextId: request.contextId
                    )
                )
                fallbackUsed = true

                eventLogger.log(
                    QuickSVOEvent(
                        name: .cloudFallbackUsed,
                        contextId: request.contextId,
                        timestamp: Date().timeIntervalSince1970,
                        metadata: [:]
                    )
                )
            }

            parsedSentences.append(
                ParseParagraphSentence(index: index, text: sentence, svo: result)
            )
        }

        let totalLatencyMs = Int(Date().timeIntervalSince(start) * 1000.0)

        eventLogger.log(
            QuickSVOEvent(
                name: .succeeded,
                contextId: contextId,
                timestamp: Date().timeIntervalSince1970,
                metadata: [
                    "sentence_count": String(parsedSentences.count),
                    "fallback_used": String(fallbackUsed)
                ]
            )
        )

        return ParseParagraphResponse(
            sentences: parsedSentences,
            totalLatencyMs: totalLatencyMs,
            fallbackUsed: fallbackUsed
        )
    }

    private func shouldUseFallback(for result: ParseSentenceResponse) -> Bool {
        guard settings.cloudFallbackEnabled else { return false }
        guard cloudParser != nil else { return false }

        return result.confidence < settings.confidenceThreshold ||
            result.subject.isEmpty ||
            result.verb.isEmpty
    }
}
