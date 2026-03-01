import Foundation

public protocol TextCaptureProviding {
    func captureText(request: CaptureTextRequest) throws -> CaptureTextResponse
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
