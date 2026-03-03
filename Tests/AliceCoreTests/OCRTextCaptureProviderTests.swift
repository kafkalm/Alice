import XCTest
@testable import AliceCore

private struct StubOCRReader: OCRTextReading {
    let output: CapturedText?

    func readText(around point: CursorPoint) -> CapturedText? {
        _ = point
        return output
    }
}

private struct StubLanguageHintProvider: LanguageHintProviding {
    let hint: LanguageHint

    func detectLanguageHint(for text: String) -> LanguageHint {
        _ = text
        return hint
    }
}

final class OCRTextCaptureProviderTests: XCTestCase {
    func testReturnsOCRResultWhenTextAvailable() throws {
        let provider = OCRTextCaptureProvider(
            ocrReader: StubOCRReader(output: CapturedText(text: "She sent the summary to the team.", bounds: RectBounds(x: 1, y: 2, width: 3, height: 4))),
            languageHintProvider: StubLanguageHintProvider(hint: .en)
        )

        let result = try provider.captureText(
            request: CaptureTextRequest(
                sourceApp: "Preview",
                cursorPoint: CursorPoint(x: 99, y: 42),
                timestamp: Date().timeIntervalSince1970
            )
        )

        XCTAssertEqual(result.method, .ocr)
        XCTAssertEqual(result.rawText, "She sent the summary to the team.")
        XCTAssertEqual(result.bounds, RectBounds(x: 1, y: 2, width: 3, height: 4))
    }

    func testTrimsOCRResult() throws {
        let provider = OCRTextCaptureProvider(
            ocrReader: StubOCRReader(output: CapturedText(text: "  OCR text should be used.\n", bounds: nil)),
            languageHintProvider: StubLanguageHintProvider(hint: .en)
        )

        let result = try provider.captureText(
            request: CaptureTextRequest(
                sourceApp: "Arc",
                cursorPoint: CursorPoint(x: 10, y: 20),
                timestamp: Date().timeIntervalSince1970
            )
        )

        XCTAssertEqual(result.method, .ocr)
        XCTAssertEqual(result.rawText, "OCR text should be used.")
    }

    func testThrowsWhenNoTextDetected() {
        let provider = OCRTextCaptureProvider(
            ocrReader: StubOCRReader(output: nil),
            languageHintProvider: StubLanguageHintProvider(hint: .unknown)
        )

        XCTAssertThrowsError(
            try provider.captureText(
                request: CaptureTextRequest(
                    sourceApp: "Mail",
                    cursorPoint: CursorPoint(x: 0, y: 0),
                    timestamp: Date().timeIntervalSince1970
                )
            )
        ) { error in
            XCTAssertEqual(error as? QuickSVOError, .noTextDetected)
        }
    }
}
