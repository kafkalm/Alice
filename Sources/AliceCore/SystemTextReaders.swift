import ApplicationServices
import Foundation

public struct AXFocusedTextReader: AccessibilityTextReading {
    public typealias DiagnosticsHandler = @Sendable (String) -> Void

    private let diagnostics: DiagnosticsHandler?

    public init(diagnostics: DiagnosticsHandler? = nil) {
        self.diagnostics = diagnostics
    }

    public func readFocusedText() -> CapturedText? {
        let systemWide = AXUIElementCreateSystemWide()

        guard let focused = copyAXElement(from: systemWide, attribute: kAXFocusedUIElementAttribute as CFString, label: "focusedUIElement") else {
            diagnostics?("AX read failed: focused UI element unavailable")
            return nil
        }

        if let selectedText = copyString(from: focused, attribute: kAXSelectedTextAttribute as CFString, label: "selectedText") {
            let normalized = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty {
                diagnostics?("AX selectedText captured length=\(normalized.count)")
                return CapturedText(text: selectedText, bounds: copyBounds(from: focused))
            }
            diagnostics?("AX selectedText present but empty after trim")
        }

        if let valueText = copyString(from: focused, attribute: kAXValueAttribute as CFString, label: "valueText") {
            let normalized = valueText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty {
                diagnostics?("AX valueText captured length=\(normalized.count)")
                return CapturedText(text: valueText, bounds: copyBounds(from: focused))
            }
            diagnostics?("AX valueText present but empty after trim")
        }

        diagnostics?("AX read produced no usable text")
        return nil
    }

    private func copyAXElement(from element: AXUIElement, attribute: CFString, label: String) -> AXUIElement? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success else {
            diagnostics?("AX attribute \(label) status=\(status.rawValue)")
            return nil
        }
        guard let value else {
            diagnostics?("AX attribute \(label) returned nil")
            return nil
        }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            diagnostics?("AX attribute \(label) type mismatch")
            return nil
        }
        return (value as! AXUIElement)
    }

    private func copyString(from element: AXUIElement, attribute: CFString, label: String) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success else {
            diagnostics?("AX attribute \(label) status=\(status.rawValue)")
            return nil
        }

        if let result = value as? String {
            return result
        }
        diagnostics?("AX attribute \(label) non-string value")
        return nil
    }

    private func copyBounds(from element: AXUIElement) -> RectBounds? {
        guard let position = copyPoint(from: element, attribute: kAXPositionAttribute as CFString),
              let size = copySize(from: element, attribute: kAXSizeAttribute as CFString)
        else {
            return nil
        }

        return RectBounds(
            x: position.x,
            y: position.y,
            width: size.width,
            height: size.height
        )
    }

    private func copyPoint(from element: AXUIElement, attribute: CFString) -> CGPoint? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success, let value else {
            return nil
        }
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }

        return point
    }

    private func copySize(from element: AXUIElement, attribute: CFString) -> CGSize? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success, let value else {
            return nil
        }
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }

        return size
    }
}
