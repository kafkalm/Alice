import CoreGraphics
import Foundation
import ScreenCaptureKit
import Vision

public struct VisionOCRTextReader: OCRTextReading {
    private let captureSize: CGSize
    private let regionCapturer: (CGRect) -> CGImage?
    private let recognizer: (CGImage) -> String?

    public init(
        captureSize: CGSize = CGSize(width: 820, height: 260),
        regionCapturer: @escaping (CGRect) -> CGImage?,
        recognizer: @escaping (CGImage) -> String?
    ) {
        self.captureSize = captureSize
        self.regionCapturer = regionCapturer
        self.recognizer = recognizer
    }

    public init(
        captureSize: CGSize = CGSize(width: 820, height: 260),
        regionCapturer: ScreenRegionCapturing = ScreenCaptureKitRegionCapturer(),
        recognizer: OCRRecognizing = VisionOCRRecognizer()
    ) {
        self.init(
            captureSize: captureSize,
            regionCapturer: { rect in
                regionCapturer.captureImage(in: rect)
            },
            recognizer: { image in
                recognizer.recognizeText(in: image)
            }
        )
    }

    public func readText(around point: CursorPoint) -> CapturedText? {
        let rect = CGRect(
            x: point.x - (captureSize.width / 2.0),
            y: point.y - (captureSize.height / 2.0),
            width: captureSize.width,
            height: captureSize.height
        ).integral

        guard rect.width > 2, rect.height > 2 else {
            return nil
        }

        guard let image = regionCapturer(rect) else {
            return nil
        }

        guard let rawText = recognizer(image) else {
            return nil
        }

        let normalized = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }

        return CapturedText(
            text: normalized,
            bounds: RectBounds(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
        )
    }
}

public final class ScreenCaptureKitRegionCapturer: ScreenRegionCapturing {
    public typealias AsyncCapture = @Sendable (CGRect) async throws -> CGImage?

    private let timeoutSeconds: TimeInterval
    private let asyncCapture: AsyncCapture

    public init(
        timeoutSeconds: TimeInterval = 1.5,
        asyncCapture: AsyncCapture? = nil
    ) {
        self.timeoutSeconds = timeoutSeconds
        self.asyncCapture = asyncCapture ?? Self.captureUsingScreenCaptureKit
    }

    public func captureImage(in rect: CGRect) -> CGImage? {
        let semaphore = DispatchSemaphore(value: 0)
        let box = CaptureResultBox()
        let asyncCapture = self.asyncCapture

        Task.detached {
            do {
                box.set(try await asyncCapture(rect))
            } catch {
                box.set(nil)
            }
            semaphore.signal()
        }

        let timeout = DispatchTime.now() + timeoutSeconds
        guard semaphore.wait(timeout: timeout) == .success else {
            return nil
        }

        return box.get()
    }

    static func captureUsingScreenCaptureKit(in rect: CGRect) async throws -> CGImage? {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = pickDisplay(for: rect, displays: content.displays) else {
            return nil
        }

        let displayFrame = CGRect(x: display.frame.origin.x, y: display.frame.origin.y, width: display.frame.width, height: display.frame.height)
        let sourceRect = normalize(rect: rect, within: displayFrame)
        guard sourceRect.width > 2, sourceRect.height > 2 else {
            return nil
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(sourceRect.width.rounded(.up))
        config.height = Int(sourceRect.height.rounded(.up))
        config.sourceRect = sourceRect

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    private static func pickDisplay(for rect: CGRect, displays: [SCDisplay]) -> SCDisplay? {
        let center = CGPoint(x: rect.midX, y: rect.midY)

        if let exact = displays.first(where: { display in
            let frame = CGRect(x: display.frame.origin.x, y: display.frame.origin.y, width: display.frame.width, height: display.frame.height)
            return frame.contains(center)
        }) {
            return exact
        }

        return displays.first
    }

    private static func normalize(rect: CGRect, within displayFrame: CGRect) -> CGRect {
        let intersection = rect.intersection(displayFrame)
        guard !intersection.isNull, !intersection.isEmpty else {
            return .null
        }

        let local = CGRect(
            x: intersection.origin.x - displayFrame.origin.x,
            y: intersection.origin.y - displayFrame.origin.y,
            width: intersection.size.width,
            height: intersection.size.height
        )

        return local.integral
    }
}

private final class CaptureResultBox: @unchecked Sendable {
    private var image: CGImage?
    private let lock = NSLock()

    func set(_ image: CGImage?) {
        lock.lock()
        self.image = image
        lock.unlock()
    }

    func get() -> CGImage? {
        lock.lock()
        let image = self.image
        lock.unlock()
        return image
    }
}

public struct VisionOCRRecognizer: OCRRecognizing {
    public init() {}

    public func recognizeText(in image: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US", "en-GB"]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observations = request.results, !observations.isEmpty else {
            return nil
        }

        let lines = observations.compactMap { observation in
            observation.topCandidates(1).first?.string
        }

        let output = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }
}

public struct NoopOCRTextReader: OCRTextReading {
    public init() {}

    public func readText(around point: CursorPoint) -> CapturedText? {
        _ = point
        return nil
    }
}
