import Foundation

public protocol TextCaptureProviding {
    func captureText(request: CaptureTextRequest) throws -> CaptureTextResponse
}

public protocol AccessibilityTextReading {
    func readFocusedText() -> CapturedText?
}

public protocol OCRTextReading {
    func readText(around point: CursorPoint) -> CapturedText?
}

public protocol LanguageHintProviding {
    func detectLanguageHint(for text: String) -> LanguageHint
}

public protocol SentenceSplitting {
    func split(_ text: String) -> [String]
}

public protocol SentenceParsing {
    func parse(_ request: ParseSentenceRequest) -> ParseSentenceResponse
}

public protocol EventLogging {
    func log(_ event: QuickSVOEvent)
}
