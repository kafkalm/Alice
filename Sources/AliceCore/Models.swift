import Foundation

public struct CursorPoint: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct RectBounds: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct CapturedText: Codable, Equatable, Sendable {
    public let text: String
    public let bounds: RectBounds?

    public init(text: String, bounds: RectBounds?) {
        self.text = text
        self.bounds = bounds
    }
}

public enum CaptureMethod: String, Codable, Equatable, Sendable {
    case ocr
}

public enum LanguageHint: String, Codable, Equatable, Sendable {
    case en
    case unknown
}

public struct CaptureTextRequest: Codable, Equatable, Sendable {
    public let sourceApp: String
    public let cursorPoint: CursorPoint
    public let timestamp: TimeInterval

    public init(sourceApp: String, cursorPoint: CursorPoint, timestamp: TimeInterval) {
        self.sourceApp = sourceApp
        self.cursorPoint = cursorPoint
        self.timestamp = timestamp
    }
}

public struct CaptureTextResponse: Codable, Equatable, Sendable {
    public let method: CaptureMethod
    public let rawText: String
    public let languageHint: LanguageHint
    public let bounds: RectBounds?

    public init(method: CaptureMethod, rawText: String, languageHint: LanguageHint, bounds: RectBounds?) {
        self.method = method
        self.rawText = rawText
        self.languageHint = languageHint
        self.bounds = bounds
    }
}

public enum ParseMode: String, Codable, Equatable, Sendable {
    case local
    case cloudFallback = "cloud_fallback"
}

public struct ParseSentenceRequest: Codable, Equatable, Sendable {
    public let sentence: String
    public let mode: ParseMode
    public let contextId: String

    public init(sentence: String, mode: ParseMode, contextId: String) {
        self.sentence = sentence
        self.mode = mode
        self.contextId = contextId
    }
}

public struct ParseSentenceResponse: Codable, Equatable, Sendable {
    public let subject: String
    public let verb: String
    public let object: String
    public let confidence: Double
    public let notes: String?

    public init(subject: String, verb: String, object: String, confidence: Double, notes: String? = nil) {
        self.subject = subject
        self.verb = verb
        self.object = object
        self.confidence = confidence
        self.notes = notes
    }
}

public struct ParseParagraphSentence: Codable, Equatable, Sendable {
    public let index: Int
    public let text: String
    public let svo: ParseSentenceResponse

    public init(index: Int, text: String, svo: ParseSentenceResponse) {
        self.index = index
        self.text = text
        self.svo = svo
    }
}

public struct ParseParagraphResponse: Codable, Equatable, Sendable {
    public let sentences: [ParseParagraphSentence]
    public let totalLatencyMs: Int
    public let fallbackUsed: Bool

    public init(sentences: [ParseParagraphSentence], totalLatencyMs: Int, fallbackUsed: Bool) {
        self.sentences = sentences
        self.totalLatencyMs = totalLatencyMs
        self.fallbackUsed = fallbackUsed
    }
}

public struct QuickSVOSettings: Equatable, Sendable {
    public let cloudFallbackEnabled: Bool
    public let confidenceThreshold: Double

    public init(cloudFallbackEnabled: Bool = false, confidenceThreshold: Double = 0.55) {
        self.cloudFallbackEnabled = cloudFallbackEnabled
        self.confidenceThreshold = confidenceThreshold
    }
}

public enum QuickSVOEventName: String, Codable, Equatable, Sendable {
    case triggered = "alice.quick_svo.triggered"
    case succeeded = "alice.quick_svo.succeeded"
    case failed = "alice.quick_svo.failed"
    case cloudFallbackUsed = "alice.quick_svo.cloud_fallback_used"
}

public struct QuickSVOEvent: Codable, Equatable, Sendable {
    public let name: QuickSVOEventName
    public let contextId: String
    public let timestamp: TimeInterval
    public let metadata: [String: String]

    public init(name: QuickSVOEventName, contextId: String, timestamp: TimeInterval, metadata: [String: String] = [:]) {
        self.name = name
        self.contextId = contextId
        self.timestamp = timestamp
        self.metadata = metadata
    }
}

public enum QuickSVOError: LocalizedError, Equatable {
    case noTextDetected

    public var errorDescription: String? {
        switch self {
        case .noTextDetected:
            return "No parseable English text detected."
        }
    }
}
