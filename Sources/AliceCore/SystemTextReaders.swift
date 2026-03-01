import ApplicationServices
import Foundation

public struct AXFocusedTextReader: AccessibilityTextReading {
    public init() {}

    public func readFocusedText() -> CapturedText? {
        let systemWide = AXUIElementCreateSystemWide()

        guard let focused = copyAXElement(from: systemWide, attribute: kAXFocusedUIElementAttribute as CFString) else {
            return nil
        }

        if let selectedText = copyString(from: focused, attribute: kAXSelectedTextAttribute as CFString),
           !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return CapturedText(text: selectedText, bounds: copyBounds(from: focused))
        }

        if let valueText = copyString(from: focused, attribute: kAXValueAttribute as CFString),
           !valueText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return CapturedText(text: valueText, bounds: copyBounds(from: focused))
        }

        return nil
    }

    private func copyAXElement(from element: AXUIElement, attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success else { return nil }
        return value as! AXUIElement?
    }

    private func copyString(from element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success else { return nil }

        if let result = value as? String {
            return result
        }
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
