import CoreGraphics
import XCTest
@testable import AliceCore

private final class StubScreenCapturer: ScreenRegionCapturing {
    let image: CGImage?
    private(set) var capturedRects: [CGRect] = []

    init(image: CGImage?) {
        self.image = image
    }

    func captureImage(in rect: CGRect) -> CGImage? {
        capturedRects.append(rect)
        return image
    }
}

private struct StubOCRRecognizer: OCRRecognizing {
    let text: String?

    func recognizeText(in image: CGImage) -> String? {
        _ = image
        return text
    }
}

final class VisionOCRTextReaderTests: XCTestCase {
    func testReturnsCapturedTextWithConfiguredBounds() {
        let capturer = StubScreenCapturer(image: Self.make1x1Image())
        let recognizer = StubOCRRecognizer(text: "  The team shipped the release. ")

        let reader = VisionOCRTextReader(
            captureSize: CGSize(width: 200, height: 80),
            regionCapturer: { rect in
                capturer.captureImage(in: rect)
            },
            recognizer: { image in
                recognizer.recognizeText(in: image)
            }
        )

        let result = reader.readText(around: CursorPoint(x: 300, y: 500))

        XCTAssertEqual(result?.text, "The team shipped the release.")
        XCTAssertEqual(result?.bounds, RectBounds(x: 200, y: 460, width: 200, height: 80))
        XCTAssertEqual(capturer.capturedRects.count, 1)
    }

    func testReturnsNilWhenCaptureFails() {
        let capturer = StubScreenCapturer(image: nil)
        let reader = VisionOCRTextReader(
            captureSize: CGSize(width: 120, height: 60),
            regionCapturer: { rect in
                capturer.captureImage(in: rect)
            },
            recognizer: { _ in
                "ignored"
            }
        )

        let result = reader.readText(around: CursorPoint(x: 20, y: 20))
        XCTAssertNil(result)
    }

    func testReturnsNilWhenOCRTextIsEmpty() {
        let capturer = StubScreenCapturer(image: Self.make1x1Image())
        let reader = VisionOCRTextReader(
            captureSize: CGSize(width: 120, height: 60),
            regionCapturer: { rect in
                capturer.captureImage(in: rect)
            },
            recognizer: { _ in
                "   "
            }
        )

        let result = reader.readText(around: CursorPoint(x: 20, y: 20))
        XCTAssertNil(result)
    }

    private static func make1x1Image() -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )!
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return context.makeImage()!
    }
}
