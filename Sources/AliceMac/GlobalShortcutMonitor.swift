import AppKit

final class GlobalShortcutMonitor {
    typealias DiagnosticsHandler = @Sendable (String) -> Void

    private let keyCode: UInt16
    private let modifiers: NSEvent.ModifierFlags
    private let handler: @MainActor @Sendable () -> Void
    private let diagnostics: DiagnosticsHandler?

    private var globalMonitorToken: Any?
    private var localMonitorToken: Any?

    var isRunning: Bool {
        globalMonitorToken != nil || localMonitorToken != nil
    }

    init(
        keyCode: UInt16 = 0,
        modifiers: NSEvent.ModifierFlags = [.command, .shift],
        handler: @escaping @MainActor @Sendable () -> Void,
        diagnostics: DiagnosticsHandler? = nil
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.handler = handler
        self.diagnostics = diagnostics
    }

    func start() {
        guard globalMonitorToken == nil, localMonitorToken == nil else {
            notifyDiagnostics("start() ignored: monitor already running")
            return
        }

        let keyCode = self.keyCode
        let modifiers = self.modifiers
        let callback = self.handler
        let diagnostics = self.diagnostics

        notifyDiagnostics("start() keyCode=\(keyCode) modifiers=\(Self.describe(modifiers: modifiers))")

        globalMonitorToken = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            let isMatch = Self.matchesShortcut(event, keyCode: keyCode, modifiers: modifiers)
            if isMatch || Self.shouldLog(event, expectedKeyCode: keyCode, expectedModifiers: modifiers) {
                let message = "global keyDown keyCode=\(event.keyCode) modifiers=\(Self.describe(modifiers: event.modifierFlags)) matched=\(isMatch)"
                diagnostics?(message)
            }
            guard isMatch else { return }
            Task { @MainActor in
                callback()
            }
        }

        localMonitorToken = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let isMatch = Self.matchesShortcut(event, keyCode: keyCode, modifiers: modifiers)
            if isMatch || Self.shouldLog(event, expectedKeyCode: keyCode, expectedModifiers: modifiers) {
                let message = "local keyDown keyCode=\(event.keyCode) modifiers=\(Self.describe(modifiers: event.modifierFlags)) matched=\(isMatch)"
                diagnostics?(message)
            }
            guard isMatch else { return event }
            Task { @MainActor in
                callback()
            }
            return event
        }

        notifyDiagnostics("start() completed running=\(isRunning)")
    }

    func stop() {
        notifyDiagnostics("stop() called")
        if let globalMonitorToken {
            NSEvent.removeMonitor(globalMonitorToken)
            self.globalMonitorToken = nil
        }
        if let localMonitorToken {
            NSEvent.removeMonitor(localMonitorToken)
            self.localMonitorToken = nil
        }
    }

    deinit {
        stop()
    }

    private static func matchesShortcut(_ event: NSEvent, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let normalized = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .intersection(relevantModifiers)
        let expected = modifiers.intersection(relevantModifiers)

        return event.keyCode == keyCode && normalized == expected
    }

    private static func shouldLog(
        _ event: NSEvent,
        expectedKeyCode: UInt16,
        expectedModifiers: NSEvent.ModifierFlags
    ) -> Bool {
        let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let normalized = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .intersection(relevantModifiers)
        let expected = expectedModifiers.intersection(relevantModifiers)

        return event.keyCode == expectedKeyCode || !normalized.isDisjoint(with: expected)
    }

    private static func describe(modifiers: NSEvent.ModifierFlags) -> String {
        let normalized = modifiers.intersection([.command, .option, .control, .shift])
        var labels: [String] = []
        if normalized.contains(.command) { labels.append("cmd") }
        if normalized.contains(.option) { labels.append("opt") }
        if normalized.contains(.control) { labels.append("ctrl") }
        if normalized.contains(.shift) { labels.append("shift") }
        return labels.isEmpty ? "none" : labels.joined(separator: "+")
    }

    private func notifyDiagnostics(_ message: String) {
        diagnostics?(message)
    }
}
