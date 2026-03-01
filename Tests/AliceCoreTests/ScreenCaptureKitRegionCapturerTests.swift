import CoreGraphics
import XCTest
@testable import AliceCore

final class ScreenCaptureKitRegionCapturerTests: XCTestCase {
    func testReturnsImageFromInjectedAsyncCapturer() {
        let expectedImage = Self.make1x1Image()
        let capturer = ScreenCaptureKitRegionCapturer(timeoutSeconds: 0.2) { rect in
            _ = rect
            return expectedImage
        }

        let result = capturer.captureImage(in: CGRect(x: 1, y: 2, width: 30, height: 20))

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.width, 1)
        XCTAssertEqual(result?.height, 1)
    }

    func testReturnsNilWhenInjectedCapturerThrows() {
        enum TestError: Error {
            case failed
        }

        let capturer = ScreenCaptureKitRegionCapturer(timeoutSeconds: 0.2) { _ in
            throw TestError.failed
        }

        let result = capturer.captureImage(in: CGRect(x: 1, y: 2, width: 30, height: 20))

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
