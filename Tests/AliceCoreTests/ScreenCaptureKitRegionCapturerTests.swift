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

    func testSourceRectUsesTopLeftCoordinateSystemWithinDisplay() {
        let displayFrame = CGRect(x: 100, y: 50, width: 1000, height: 800)
        let requestedRect = CGRect(x: 200, y: 150, width: 300, height: 200)

        let sourceRect = ScreenCaptureKitRegionCapturer.makeSourceRect(
            from: requestedRect,
            within: displayFrame
        )

        XCTAssertEqual(sourceRect.origin.x, 100)
        XCTAssertEqual(sourceRect.origin.y, 500)
        XCTAssertEqual(sourceRect.size.width, 300)
        XCTAssertEqual(sourceRect.size.height, 200)
    }

    func testSourceRectClampsAndFlipsYForPartialIntersection() {
        let displayFrame = CGRect(x: 0, y: 0, width: 500, height: 400)
        let requestedRect = CGRect(x: 450, y: 350, width: 120, height: 120)

        let sourceRect = ScreenCaptureKitRegionCapturer.makeSourceRect(
            from: requestedRect,
            within: displayFrame
        )

        XCTAssertEqual(sourceRect.origin.x, 450)
        XCTAssertEqual(sourceRect.origin.y, 0)
        XCTAssertEqual(sourceRect.size.width, 50)
        XCTAssertEqual(sourceRect.size.height, 50)
    }

    func testConvertsScreenCaptureFrameToAppKitFrameForSecondaryDisplay() {
        let screenCaptureFrame = CGRect(x: 2560, y: 0, width: 1920, height: 1080)

        let appKitFrame = ScreenCaptureKitRegionCapturer.makeAppKitDisplayFrame(
            from: screenCaptureFrame,
            mainDisplayHeight: 1440
        )

        XCTAssertEqual(appKitFrame.origin.x, 2560)
        XCTAssertEqual(appKitFrame.origin.y, 360)
        XCTAssertEqual(appKitFrame.size.width, 1920)
        XCTAssertEqual(appKitFrame.size.height, 1080)
    }

    func testPicksDisplayContainingAppKitRectCenter() {
        let frames: [CGRect] = [
            CGRect(x: 0, y: 0, width: 2560, height: 1440),
            CGRect(x: 2560, y: 360, width: 1920, height: 1080)
        ]
        let requestedRect = CGRect(x: 3777, y: 938, width: 561, height: 221)

        let pickedIndex = ScreenCaptureKitRegionCapturer.pickDisplayIndex(
            for: requestedRect,
            displayFramesInAppKit: frames
        )

        XCTAssertEqual(pickedIndex, 1)
    }

    func testSourceRectUsesTopLeftWithinAppKitDisplayFrameFromRealLogSample() {
        let appKitDisplayFrame = CGRect(x: 2560, y: 360, width: 1920, height: 1080)
        let requestedRect = CGRect(x: 3777, y: 938, width: 561, height: 221)

        let sourceRect = ScreenCaptureKitRegionCapturer.makeSourceRect(
            from: requestedRect,
            within: appKitDisplayFrame
        )

        XCTAssertEqual(sourceRect.origin.x, 1217)
        XCTAssertEqual(sourceRect.origin.y, 281)
        XCTAssertEqual(sourceRect.size.width, 561)
        XCTAssertEqual(sourceRect.size.height, 221)
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
