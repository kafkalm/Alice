import Foundation

public protocol ParagraphParsing {
    func parseParagraph(text: String, sourceApp: String) throws -> ParseParagraphResponse
}

public struct QuickSVOCaptureRunResult: Equatable, Sendable {
    public let capture: CaptureTextResponse
    public let parse: ParseParagraphResponse

    public init(capture: CaptureTextResponse, parse: ParseParagraphResponse) {
        self.capture = capture
        self.parse = parse
    }
}

public struct QuickSVOCaptureRunner {
    private let captureProvider: TextCaptureProviding
    private let paragraphParser: ParagraphParsing

    public init(captureProvider: TextCaptureProviding, paragraphParser: ParagraphParsing) {
        self.captureProvider = captureProvider
        self.paragraphParser = paragraphParser
    }

    public func run(request: CaptureTextRequest) throws -> QuickSVOCaptureRunResult {
        let capture = try captureProvider.captureText(request: request)
        let parsed = try paragraphParser.parseParagraph(text: capture.rawText, sourceApp: request.sourceApp)
        return QuickSVOCaptureRunResult(capture: capture, parse: parsed)
    }
}
