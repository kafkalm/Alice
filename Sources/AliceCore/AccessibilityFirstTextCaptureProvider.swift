import Foundation

public struct AccessibilityFirstTextCaptureProvider: TextCaptureProviding {
    private let axReader: AccessibilityTextReading
    private let ocrReader: OCRTextReading
    private let languageHintProvider: LanguageHintProviding

    public init(
        axReader: AccessibilityTextReading,
        ocrReader: OCRTextReading,
        languageHintProvider: LanguageHintProviding
    ) {
        self.axReader = axReader
        self.ocrReader = ocrReader
        self.languageHintProvider = languageHintProvider
    }

    public init() {
        self.init(
            axReader: AXFocusedTextReader(),
            ocrReader: VisionOCRTextReader(),
            languageHintProvider: NaturalLanguageHintProvider()
        )
    }

    public func captureText(request: CaptureTextRequest) throws -> CaptureTextResponse {
        if let captured = axReader.readFocusedText() {
            let normalizedText = captured.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalizedText.isEmpty {
                return CaptureTextResponse(
                    method: .ax,
                    rawText: normalizedText,
                    languageHint: languageHintProvider.detectLanguageHint(for: normalizedText),
                    bounds: captured.bounds
                )
            }
        }

        if let captured = ocrReader.readText(around: request.cursorPoint) {
            let normalizedText = captured.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalizedText.isEmpty {
                return CaptureTextResponse(
                    method: .ocr,
                    rawText: normalizedText,
                    languageHint: languageHintProvider.detectLanguageHint(for: normalizedText),
                    bounds: captured.bounds
                )
            }
        }

        throw QuickSVOError.noTextDetected
    }
}
