import CoreGraphics
import CoreImage
import Foundation
import ScreenCaptureKit
import Vision

public struct VisionOCRTextReader: OCRTextReading {
    private let captureCandidates: [CGSize]
    private let regionCapturer: (CGRect) -> CGImage?
    private let recognizer: (CGImage) -> String?

    public init(
        captureSize: CGSize = CGSize(width: 1080, height: 520),
        additionalCaptureSizes: [CGSize] = [],
        regionCapturer: @escaping (CGRect) -> CGImage?,
        recognizer: @escaping (CGImage) -> String?
    ) {
        self.captureCandidates = [captureSize] + additionalCaptureSizes
        self.regionCapturer = regionCapturer
        self.recognizer = recognizer
    }

    public init(
        captureSize: CGSize = CGSize(width: 560, height: 220),
        regionCapturer: ScreenRegionCapturing = ScreenCaptureKitRegionCapturer(),
        recognizer: OCRRecognizing = VisionOCRRecognizer()
    ) {
        let expanded = CGSize(width: captureSize.width * 1.4, height: captureSize.height * 1.45)
        self.init(
            captureSize: captureSize,
            additionalCaptureSizes: [expanded],
            regionCapturer: { rect in
                regionCapturer.captureImage(in: rect)
            },
            recognizer: { image in
                recognizer.recognizeText(in: image)
            }
        )
    }

    public func readText(around point: CursorPoint) -> CapturedText? {
        var best: (text: String, bounds: RectBounds, score: Double)?

        for (candidateIndex, size) in captureCandidates.enumerated() where size.width > 2 && size.height > 2 {
            let rect = CGRect(
                x: point.x - (size.width / 2.0),
                y: point.y - (size.height / 2.0),
                width: size.width,
                height: size.height
            ).integral

            guard rect.width > 2, rect.height > 2 else { continue }

            guard let image = regionCapturer(rect) else { continue }
            guard let rawText = recognizer(image) else { continue }

            let normalized = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }

            let score = textQualityScore(normalized)
            let bounds = RectBounds(
                x: rect.origin.x,
                y: rect.origin.y,
                width: rect.size.width,
                height: rect.size.height
            )
            if best == nil || score > best!.score {
                best = (normalized, bounds, score)
            }

            if candidateIndex == 0, shouldAcceptNearbyCandidateImmediately(text: normalized, score: score) {
                return CapturedText(text: normalized, bounds: bounds)
            }

            // Good enough result; avoid extra OCR work.
            if score >= 12.5 {
                break
            }
        }

        guard let best else { return nil }
        return CapturedText(text: best.text, bounds: best.bounds)
    }

    private func shouldAcceptNearbyCandidateImmediately(text: String, score: Double) -> Bool {
        if score < 6.0 { return false }
        let words = text.split(whereSeparator: \.isWhitespace)
        if words.count < 2 { return false }
        return text.count >= 12
    }

    private func textQualityScore(_ text: String) -> Double {
        guard !text.isEmpty else { return 0 }
        let scalars = Array(text.unicodeScalars)
        let count = Double(scalars.count)
        let letters = Double(scalars.filter { CharacterSet.letters.contains($0) }.count)
        let punctuation = Double(scalars.filter { ".?!,:;".unicodeScalars.contains($0) }.count)
        let letterRatio = letters / max(1, count)
        let lengthScore = min(8.0, count * 0.08)
        let punctuationScore = min(2.0, punctuation * 0.2)
        return lengthScore + (letterRatio * 6.0) + punctuationScore
    }
}

public final class ScreenCaptureKitRegionCapturer: ScreenRegionCapturing {
    public typealias AsyncCapture = @Sendable (CGRect) async throws -> CGImage?
    public typealias DiagnosticsHandler = @Sendable (String) -> Void

    private let timeoutSeconds: TimeInterval
    private let asyncCapture: AsyncCapture

    public init(
        timeoutSeconds: TimeInterval = 1.5,
        asyncCapture: AsyncCapture? = nil,
        diagnostics: DiagnosticsHandler? = nil
    ) {
        self.timeoutSeconds = timeoutSeconds
        self.asyncCapture = asyncCapture ?? { rect in
            try await Self.captureUsingScreenCaptureKit(in: rect, diagnostics: diagnostics)
        }
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

    static func captureUsingScreenCaptureKit(in rect: CGRect, diagnostics: DiagnosticsHandler? = nil) async throws -> CGImage? {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let displayFrames = content.displays.map {
            CGRect(x: $0.frame.origin.x, y: $0.frame.origin.y, width: $0.frame.width, height: $0.frame.height)
        }
        guard let mainDisplayHeight = resolveMainDisplayHeight(fromScreenCaptureFrames: displayFrames) else {
            diagnostics?("ocr sc capture failed: unable to resolve main display height")
            return nil
        }

        let displayFramesInAppKit = displayFrames.map {
            makeAppKitDisplayFrame(from: $0, mainDisplayHeight: mainDisplayHeight)
        }
        guard let pickedDisplayIndex = pickDisplayIndex(for: rect, displayFramesInAppKit: displayFramesInAppKit) else {
            diagnostics?("ocr sc capture failed: unable to pick display for rect=\(describe(rect))")
            return nil
        }

        let display = content.displays[pickedDisplayIndex]
        let displayFrameInAppKit = displayFramesInAppKit[pickedDisplayIndex]
        let sourceRect = makeSourceRect(from: rect, within: displayFrameInAppKit)
        guard sourceRect.width > 2, sourceRect.height > 2 else {
            diagnostics?(
                "ocr sc capture skipped: tiny sourceRect=\(describe(sourceRect)) " +
                "requested=\(describe(rect)) displayIndex=\(pickedDisplayIndex)"
            )
            return nil
        }
        diagnostics?(
            "ocr sc capture requested=\(describe(rect)) displayIndex=\(pickedDisplayIndex) " +
            "displaySC=\(describe(displayFrames[pickedDisplayIndex])) displayApp=\(describe(displayFrameInAppKit)) " +
            "sourceRect=\(describe(sourceRect))"
        )

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(sourceRect.width.rounded(.up))
        config.height = Int(sourceRect.height.rounded(.up))
        config.sourceRect = sourceRect

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    static func resolveMainDisplayHeight(fromScreenCaptureFrames frames: [CGRect]) -> CGFloat? {
        if let main = frames.first(where: { abs($0.origin.x) < 0.5 && abs($0.origin.y) < 0.5 }) {
            return main.height
        }

        guard let fallback = frames.max(by: { ($0.width * $0.height) < ($1.width * $1.height) }) else {
            return nil
        }
        return fallback.height
    }

    static func makeAppKitDisplayFrame(from screenCaptureFrame: CGRect, mainDisplayHeight: CGFloat) -> CGRect {
        CGRect(
            x: screenCaptureFrame.origin.x,
            y: mainDisplayHeight - screenCaptureFrame.origin.y - screenCaptureFrame.height,
            width: screenCaptureFrame.width,
            height: screenCaptureFrame.height
        )
    }

    static func pickDisplayIndex(for rect: CGRect, displayFramesInAppKit: [CGRect]) -> Int? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        if let exact = displayFramesInAppKit.firstIndex(where: { $0.contains(center) }) {
            return exact
        }

        var best: (index: Int, area: CGFloat)?
        for (index, displayFrame) in displayFramesInAppKit.enumerated() {
            let intersection = rect.intersection(displayFrame)
            guard !intersection.isNull, !intersection.isEmpty else { continue }
            let area = intersection.width * intersection.height
            if let currentBest = best, area <= currentBest.area {
                continue
            }
            best = (index, area)
        }
        if let best {
            return best.index
        }

        return displayFramesInAppKit.isEmpty ? nil : 0
    }

    static func makeSourceRect(from rect: CGRect, within displayFrame: CGRect) -> CGRect {
        let intersection = rect.intersection(displayFrame)
        guard !intersection.isNull, !intersection.isEmpty else {
            return .null
        }

        let localTopLeft = CGRect(
            x: intersection.origin.x - displayFrame.origin.x,
            y: displayFrame.maxY - intersection.maxY,
            width: intersection.size.width,
            height: intersection.size.height
        )

        return localTopLeft.integral
    }

    private static func describe(_ rect: CGRect) -> String {
        "\(Int(rect.origin.x)),\(Int(rect.origin.y)),\(Int(rect.width))x\(Int(rect.height))"
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
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    public init() {}

    public func recognizeText(in image: CGImage) -> String? {
        let variants = imageVariants(for: image)
        var bestText: String?
        var bestScore: Double = 0

        for variant in variants {
            guard let output = recognizeTextWithVision(in: variant) else { continue }
            let score = score(output: output)
            if score > bestScore {
                bestScore = score
                bestText = output.text
            }
        }

        guard let bestText else { return nil }
        let normalized = bestText.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func recognizeTextWithVision(in image: CGImage) -> OCRPassResult? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.01
        request.recognitionLanguages = ["en-US", "en-GB", "zh-Hans", "zh-Hant"]
        if #available(macOS 13.0, *) {
            request.automaticallyDetectsLanguage = true
        }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observations = request.results, !observations.isEmpty else {
            return nil
        }

        let items: [RecognizedLineItem] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else {
                return nil
            }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return nil
            }
            return RecognizedLineItem(
                text: text,
                boundingBox: observation.boundingBox,
                confidence: candidate.confidence
            )
        }
        guard !items.isEmpty else { return nil }

        let rows = assembleRows(from: items)
        let output = rows.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { return nil }

        let avgConfidence = items.reduce(0.0) { $0 + Double($1.confidence) } / Double(items.count)
        return OCRPassResult(
            text: output,
            averageConfidence: avgConfidence,
            lineCount: rows.count
        )
    }

    private func assembleRows(from items: [RecognizedLineItem]) -> [String] {
        let sorted = items.sorted { lhs, rhs in
            if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.02 {
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }

        var rows: [[RecognizedLineItem]] = []
        for item in sorted {
            if let lastIndex = rows.indices.last {
                let lastMidY = rows[lastIndex].map(\.boundingBox.midY).reduce(0, +) / Double(rows[lastIndex].count)
                if abs(lastMidY - item.boundingBox.midY) <= 0.03 {
                    rows[lastIndex].append(item)
                    continue
                }
            }
            rows.append([item])
        }

        return rows.map { row in
            row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                .map(\.text)
                .joined(separator: " ")
        }
    }

    private func score(output: OCRPassResult) -> Double {
        let lengthScore = min(10.0, Double(output.text.count) * 0.08)
        let confidenceScore = output.averageConfidence * 4.0
        let lineScore = min(2.5, Double(output.lineCount) * 0.5)
        return lengthScore + confidenceScore + lineScore
    }

    private func imageVariants(for image: CGImage) -> [CGImage] {
        var variants: [CGImage] = [image]

        if let enhanced = makeEnhancedImage(
            from: image,
            contrast: 1.35,
            brightness: 0.02,
            saturation: 0.0,
            sharpenRadius: 0.0
        ) {
            variants.append(enhanced)
        }

        if let sharpened = makeEnhancedImage(
            from: image,
            contrast: 1.2,
            brightness: 0.0,
            saturation: 0.0,
            sharpenRadius: 0.9
        ) {
            variants.append(sharpened)
        }

        return variants
    }

    private func makeEnhancedImage(
        from image: CGImage,
        contrast: Double,
        brightness: Double,
        saturation: Double,
        sharpenRadius: Double
    ) -> CGImage? {
        let ciImage = CIImage(cgImage: image)

        guard let colorControls = CIFilter(name: "CIColorControls") else {
            return nil
        }
        colorControls.setValue(ciImage, forKey: kCIInputImageKey)
        colorControls.setValue(contrast, forKey: kCIInputContrastKey)
        colorControls.setValue(brightness, forKey: kCIInputBrightnessKey)
        colorControls.setValue(saturation, forKey: kCIInputSaturationKey)
        guard var outputImage = colorControls.outputImage else {
            return nil
        }

        if sharpenRadius > 0, let sharpen = CIFilter(name: "CISharpenLuminance") {
            sharpen.setValue(outputImage, forKey: kCIInputImageKey)
            sharpen.setValue(sharpenRadius, forKey: kCIInputSharpnessKey)
            if let sharpened = sharpen.outputImage {
                outputImage = sharpened
            }
        }

        return Self.ciContext.createCGImage(outputImage, from: outputImage.extent)
    }
}

private struct RecognizedLineItem {
    let text: String
    let boundingBox: CGRect
    let confidence: Float
}

private struct OCRPassResult {
    let text: String
    let averageConfidence: Double
    let lineCount: Int
}

public struct NoopOCRTextReader: OCRTextReading {
    public init() {}

    public func readText(around point: CursorPoint) -> CapturedText? {
        _ = point
        return nil
    }
}
