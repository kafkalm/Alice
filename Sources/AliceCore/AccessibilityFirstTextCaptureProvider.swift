import Foundation
@preconcurrency import ApplicationServices

public struct AccessibilityFirstTextCaptureProvider: TextCaptureProviding {
    public typealias DiagnosticsHandler = @Sendable (String) -> Void

    private let axReader: AccessibilityTextReading
    private let ocrReader: OCRTextReading
    private let languageHintProvider: LanguageHintProviding
    private let diagnostics: DiagnosticsHandler?

    public init(
        axReader: AccessibilityTextReading,
        ocrReader: OCRTextReading,
        languageHintProvider: LanguageHintProviding,
        diagnostics: DiagnosticsHandler? = nil
    ) {
        self.axReader = axReader
        self.ocrReader = ocrReader
        self.languageHintProvider = languageHintProvider
        self.diagnostics = diagnostics
    }

    public init(diagnostics: DiagnosticsHandler? = nil) {
        self.init(
            axReader: AXFocusedTextReader(diagnostics: diagnostics),
            ocrReader: VisionOCRTextReader(),
            languageHintProvider: NaturalLanguageHintProvider(),
            diagnostics: diagnostics
        )
    }

    public func captureText(request: CaptureTextRequest) throws -> CaptureTextResponse {
        diagnostics?("capture start sourceApp=\(request.sourceApp) accessibilityTrusted=\(AXIsProcessTrusted())")

        if let captured = axReader.readFocusedText() {
            let normalizedText = captured.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalizedText.isEmpty {
                diagnostics?("capture result via AX length=\(normalizedText.count)")
                return CaptureTextResponse(
                    method: .ax,
                    rawText: normalizedText,
                    languageHint: languageHintProvider.detectLanguageHint(for: normalizedText),
                    bounds: captured.bounds
                )
            }
            diagnostics?("capture AX returned text but empty after trim")
        } else {
            diagnostics?("capture AX returned nil, fallback to OCR")
        }

        if let captured = ocrReader.readText(around: request.cursorPoint) {
            let normalizedText = captured.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalizedText.isEmpty {
                diagnostics?("capture result via OCR length=\(normalizedText.count)")
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
}
