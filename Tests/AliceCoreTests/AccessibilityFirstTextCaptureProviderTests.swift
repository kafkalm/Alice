import XCTest
@testable import AliceCore

private struct StubAXReader: AccessibilityTextReading {
    let output: CapturedText?

    func readFocusedText() -> CapturedText? {
        output
    }
}

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

final class AccessibilityFirstTextCaptureProviderTests: XCTestCase {
    func testReturnsAXResultWhenAvailable() throws {
        let provider = AccessibilityFirstTextCaptureProvider(
            axReader: StubAXReader(output: CapturedText(text: "The manager approved the budget.", bounds: nil)),
            ocrReader: StubOCRReader(output: CapturedText(text: "ignored", bounds: nil)),
            languageHintProvider: StubLanguageHintProvider(hint: .en)
        )

        let result = try provider.captureText(
            request: CaptureTextRequest(
                sourceApp: "Safari",
                cursorPoint: CursorPoint(x: 10, y: 20),
                timestamp: Date().timeIntervalSince1970
            )
        )

        XCTAssertEqual(result.method, .ax)
        XCTAssertEqual(result.rawText, "The manager approved the budget.")
        XCTAssertEqual(result.languageHint, .en)
    }

    func testFallsBackToOCRWhenAXMissing() throws {
        let provider = AccessibilityFirstTextCaptureProvider(
            axReader: StubAXReader(output: nil),
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

    func testThrowsWhenNoTextDetected() {
        let provider = AccessibilityFirstTextCaptureProvider(
            axReader: StubAXReader(output: nil),
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
