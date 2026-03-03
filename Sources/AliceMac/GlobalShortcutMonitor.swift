import AppKit

final class GlobalShortcutMonitor {
    private let keyCode: UInt16
    private let modifiers: NSEvent.ModifierFlags
    private let handler: @MainActor @Sendable () -> Void

    private var globalMonitorToken: Any?
    private var localMonitorToken: Any?

    init(
        keyCode: UInt16 = 0,
        modifiers: NSEvent.ModifierFlags = [.command, .shift],
        handler: @escaping @MainActor @Sendable () -> Void
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.handler = handler
    }

    func start() {
        guard globalMonitorToken == nil, localMonitorToken == nil else { return }

        let keyCode = self.keyCode
        let modifiers = self.modifiers
        let callback = self.handler

        globalMonitorToken = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard Self.matchesShortcut(event, keyCode: keyCode, modifiers: modifiers) else { return }
            Task { @MainActor in
                callback()
            }
        }

        localMonitorToken = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard Self.matchesShortcut(event, keyCode: keyCode, modifiers: modifiers) else { return event }
            Task { @MainActor in
                callback()
            }
            return event
        }
    }

    func stop() {
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
}
