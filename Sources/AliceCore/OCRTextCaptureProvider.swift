import Foundation

public struct OCRTextCaptureProvider: TextCaptureProviding {
    public typealias DiagnosticsHandler = @Sendable (String) -> Void

    private let ocrReader: OCRTextReading
    private let languageHintProvider: LanguageHintProviding
    private let diagnostics: DiagnosticsHandler?

    public init(
        ocrReader: OCRTextReading,
        languageHintProvider: LanguageHintProviding,
        diagnostics: DiagnosticsHandler? = nil
    ) {
        self.ocrReader = ocrReader
        self.languageHintProvider = languageHintProvider
        self.diagnostics = diagnostics
    }

    public init(diagnostics: DiagnosticsHandler? = nil) {
        self.init(
            ocrReader: VisionOCRTextReader(
                regionCapturer: ScreenCaptureKitRegionCapturer(diagnostics: diagnostics),
                recognizer: VisionOCRRecognizer()
            ),
            languageHintProvider: NaturalLanguageHintProvider(),
            diagnostics: diagnostics
        )
    }

    public func captureText(request: CaptureTextRequest) throws -> CaptureTextResponse {
        diagnostics?("capture start sourceApp=\(request.sourceApp) captureMode=ocr-only")

        if let captured = ocrReader.readText(around: request.cursorPoint) {
            let normalizedText = captured.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalizedText.isEmpty {
                diagnostics?(
                    "capture result via OCR length=\(normalizedText.count) " +
                    "cursor=\(Int(request.cursorPoint.x)),\(Int(request.cursorPoint.y)) " +
                    "bounds=\(describe(captured.bounds)) " +
                    "centerDelta=\(describeCenterDelta(cursor: request.cursorPoint, bounds: captured.bounds)) " +
                    "textPreview=\"\(preview(normalizedText))\""
                )
                return CaptureTextResponse(
                    method: .ocr,
                    rawText: normalizedText,
                    languageHint: languageHintProvider.detectLanguageHint(for: normalizedText),
                    bounds: captured.bounds
                )
            }
            diagnostics?("capture OCR returned text but empty after trim")
        } else {
            diagnostics?("capture OCR returned nil")
        }

        diagnostics?("capture failed: no text detected")
        throw QuickSVOError.noTextDetected
    }

    private func describe(_ bounds: RectBounds?) -> String {
        guard let bounds else { return "nil" }
        return "\(Int(bounds.x)),\(Int(bounds.y)),\(Int(bounds.width))x\(Int(bounds.height))"
    }

    private func describeCenterDelta(cursor: CursorPoint, bounds: RectBounds?) -> String {
        guard let bounds else { return "nil" }
        let centerX = bounds.x + (bounds.width / 2.0)
        let centerY = bounds.y + (bounds.height / 2.0)
        let dx = Int((centerX - cursor.x).rounded())
        let dy = Int((centerY - cursor.y).rounded())
        return "\(dx),\(dy)"
    }

    private func preview(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.count <= 80 { return normalized }
        let end = normalized.index(normalized.startIndex, offsetBy: 80)
        return String(normalized[..<end]) + "..."
    }
}
