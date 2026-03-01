import XCTest
@testable import AliceCore

private struct StubSentenceSplitter: SentenceSplitting {
    let output: [String]

    func split(_ text: String) -> [String] {
        _ = text
        return output
    }
}

private final class RecordingParser: SentenceParsing {
    private let response: ParseSentenceResponse
    private(set) var calls: [ParseSentenceRequest] = []

    init(response: ParseSentenceResponse) {
        self.response = response
    }

    func parse(_ request: ParseSentenceRequest) -> ParseSentenceResponse {
        calls.append(request)
        return response
    }
}

private final class RecordingEventLogger: EventLogging {
    private(set) var events: [QuickSVOEvent] = []

    func log(_ event: QuickSVOEvent) {
        events.append(event)
    }
}

final class QuickSVOServiceTests: XCTestCase {
    func testUsesCloudFallbackWhenLocalConfidenceIsLow() throws {
        let local = RecordingParser(
            response: ParseSentenceResponse(subject: "", verb: "approved", object: "", confidence: 0.2)
        )
        let cloud = RecordingParser(
            response: ParseSentenceResponse(subject: "manager", verb: "approved", object: "budget", confidence: 0.9)
        )
        let logger = RecordingEventLogger()

        let service = QuickSVOService(
            sentenceSplitter: StubSentenceSplitter(output: ["The manager approved the budget."]),
            localParser: local,
            cloudParser: cloud,
            eventLogger: logger,
            settings: QuickSVOSettings(cloudFallbackEnabled: true, confidenceThreshold: 0.55)
        )

        let response = try service.parseParagraph(text: "ignored", sourceApp: "UnitTest")

        XCTAssertTrue(response.fallbackUsed)
        XCTAssertEqual(local.calls.count, 1)
        XCTAssertEqual(cloud.calls.count, 1)
        XCTAssertEqual(response.sentences.first?.svo.subject, "manager")
        XCTAssertEqual(response.sentences.first?.svo.confidence, 0.9)
        XCTAssertTrue(logger.events.contains(where: { $0.name == .cloudFallbackUsed }))
    }

    func testDoesNotUseFallbackWhenDisabled() throws {
        let local = RecordingParser(
            response: ParseSentenceResponse(subject: "manager", verb: "approved", object: "budget", confidence: 0.3)
        )
        let cloud = RecordingParser(
            response: ParseSentenceResponse(subject: "manager", verb: "approved", object: "budget", confidence: 0.9)
        )

        let service = QuickSVOService(
            sentenceSplitter: StubSentenceSplitter(output: ["The manager approved the budget."]),
            localParser: local,
            cloudParser: cloud,
            eventLogger: RecordingEventLogger(),
            settings: QuickSVOSettings(cloudFallbackEnabled: false, confidenceThreshold: 0.55)
        )

        let response = try service.parseParagraph(text: "ignored", sourceApp: "UnitTest")

        XCTAssertFalse(response.fallbackUsed)
        XCTAssertEqual(local.calls.count, 1)
        XCTAssertEqual(cloud.calls.count, 0)
        XCTAssertEqual(response.sentences.first?.svo.confidence, 0.3)
    }

    func testThrowsWhenTextIsEmpty() {
        let service = QuickSVOService(
            sentenceSplitter: StubSentenceSplitter(output: []),
            localParser: RecordingParser(response: ParseSentenceResponse(subject: "", verb: "", object: "", confidence: 0.0)),
            eventLogger: RecordingEventLogger()
        )

        XCTAssertThrowsError(try service.parseParagraph(text: "   ", sourceApp: "UnitTest")) { error in
            XCTAssertEqual(error as? QuickSVOError, .noTextDetected)
        }
    }
}
