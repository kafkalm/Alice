import XCTest
@testable import AliceCore

private struct StubCaptureProvider: TextCaptureProviding {
    let response: CaptureTextResponse

    func captureText(request: CaptureTextRequest) throws -> CaptureTextResponse {
        _ = request
        return response
    }
}

private struct ThrowingCaptureProvider: TextCaptureProviding {
    func captureText(request: CaptureTextRequest) throws -> CaptureTextResponse {
        _ = request
        throw QuickSVOError.noTextDetected
    }
}

private final class RecordingParagraphParser: ParagraphParsing {
    private let output: ParseParagraphResponse
    private(set) var requests: [(text: String, sourceApp: String)] = []

    init(output: ParseParagraphResponse) {
        self.output = output
    }

    func parseParagraph(text: String, sourceApp: String) throws -> ParseParagraphResponse {
        requests.append((text, sourceApp))
        return output
    }
}

final class QuickSVOCaptureRunnerTests: XCTestCase {
    func testCapturesAndParsesInOneRun() throws {
        let parser = RecordingParagraphParser(
            output: ParseParagraphResponse(
                sentences: [
                    ParseParagraphSentence(
                        index: 0,
                        text: "The manager approved the budget.",
                        svo: ParseSentenceResponse(subject: "manager", verb: "approved", object: "budget", confidence: 0.9)
                    )
                ],
                totalLatencyMs: 10,
                fallbackUsed: false
            )
        )

        let runner = QuickSVOCaptureRunner(
            captureProvider: StubCaptureProvider(
                response: CaptureTextResponse(method: .ocr, rawText: "The manager approved the budget.", languageHint: .en, bounds: nil)
            ),
            paragraphParser: parser
        )

        let result = try runner.run(
            request: CaptureTextRequest(
                sourceApp: "Safari",
                cursorPoint: CursorPoint(x: 1, y: 2),
                timestamp: Date().timeIntervalSince1970
            )
        )

        XCTAssertEqual(result.capture.method, .ocr)
        XCTAssertEqual(result.parse.sentences.count, 1)
        XCTAssertEqual(parser.requests.count, 1)
        XCTAssertEqual(parser.requests[0].text, "The manager approved the budget.")
        XCTAssertEqual(parser.requests[0].sourceApp, "Safari")
    }

    func testPropagatesCaptureError() {
        let parser = RecordingParagraphParser(
            output: ParseParagraphResponse(sentences: [], totalLatencyMs: 0, fallbackUsed: false)
        )

        let runner = QuickSVOCaptureRunner(
            captureProvider: ThrowingCaptureProvider(),
            paragraphParser: parser
        )

        XCTAssertThrowsError(
            try runner.run(
                request: CaptureTextRequest(
                    sourceApp: "Mail",
                    cursorPoint: CursorPoint(x: 0, y: 0),
                    timestamp: Date().timeIntervalSince1970
                )
            )
        ) { error in
            XCTAssertEqual(error as? QuickSVOError, .noTextDetected)
        }

        XCTAssertTrue(parser.requests.isEmpty)
    }
}
