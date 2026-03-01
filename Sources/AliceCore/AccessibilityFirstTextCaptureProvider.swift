import Foundation

public struct AccessibilityFirstTextCaptureProvider: TextCaptureProviding {
    public init() {}

    public func captureText(request: CaptureTextRequest) throws -> CaptureTextResponse {
        // Placeholder for AX API + OCR fallback implementation.
        throw QuickSVOError.noTextDetected
    }
}
