import CoreGraphics
import Foundation
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
        regionCapturer: ScreenRegionCapturing = QuartzScreenRegionCapturer(),
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

public struct QuartzScreenRegionCapturer: ScreenRegionCapturing {
    public init() {}

    public func captureImage(in rect: CGRect) -> CGImage? {
        CGWindowListCreateImage(
            rect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution, .boundsIgnoreFraming]
        )
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
