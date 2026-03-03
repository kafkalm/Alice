import AliceCore
import AppKit
import CoreGraphics
import SwiftUI

@MainActor
final class AliceDiagnosticsLogger {
    static let shared = AliceDiagnosticsLogger()

    let logFilePath: String

    private let logURL: URL
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private init() {
        let logsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Alice", isDirectory: true)
        self.logURL = logsDirectory.appendingPathComponent("diagnostics.log", isDirectory: false)
        self.logFilePath = logURL.path

        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
    }

    func log(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                print("AliceDiagnosticsLogger write failed: \(error.localizedDescription)")
            }
        }
        print("[AliceDiag] \(message)")
    }
}

@MainActor
protocol OCRDebugOverlayPresenting {
    func present(bounds: RectBounds, cursorPoint: CursorPoint)
}

@MainActor
final class OCRDebugOverlayManager: OCRDebugOverlayPresenting {
    private var panel: NSPanel?
    private var autoDismissWorkItem: DispatchWorkItem?

    func present(bounds: RectBounds, cursorPoint: CursorPoint) {
        guard bounds.width > 2, bounds.height > 2 else { return }

        let frame = NSRect(
            x: bounds.x,
            y: bounds.y,
            width: bounds.width,
            height: bounds.height
        ).integral

        let panel = ensurePanel()
        let overlayView = OCRDebugOverlayView(frame: NSRect(origin: .zero, size: frame.size))
        overlayView.captureFrameInScreen = frame
        overlayView.cursorPointInScreen = CGPoint(x: cursorPoint.x, y: cursorPoint.y)
        panel.contentView = overlayView
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()

        scheduleAutoDismiss()
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        self.panel = panel
        return panel
    }

    private func scheduleAutoDismiss() {
        autoDismissWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
        }
        autoDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: workItem)
    }
}

private final class OCRDebugOverlayView: NSView {
    var captureFrameInScreen: NSRect = .zero
    var cursorPointInScreen: CGPoint = .zero

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let rect = bounds.insetBy(dx: 1.5, dy: 1.5)
        NSColor.systemYellow.withAlphaComponent(0.10).setFill()
        rect.fill()

        let border = NSBezierPath(rect: rect)
        border.lineWidth = 3
        NSColor.systemRed.withAlphaComponent(0.95).setStroke()
        border.stroke()

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let centerPath = NSBezierPath()
        centerPath.move(to: CGPoint(x: center.x - 10, y: center.y))
        centerPath.line(to: CGPoint(x: center.x + 10, y: center.y))
        centerPath.move(to: CGPoint(x: center.x, y: center.y - 10))
        centerPath.line(to: CGPoint(x: center.x, y: center.y + 10))
        centerPath.lineWidth = 1.5
        NSColor.systemRed.withAlphaComponent(0.85).setStroke()
        centerPath.stroke()

        let localCursor = CGPoint(
            x: cursorPointInScreen.x - captureFrameInScreen.origin.x,
            y: cursorPointInScreen.y - captureFrameInScreen.origin.y
        )
        if rect.contains(localCursor) {
            let cursorMarker = NSBezierPath(ovalIn: NSRect(x: localCursor.x - 4, y: localCursor.y - 4, width: 8, height: 8))
            NSColor.systemBlue.setFill()
            cursorMarker.fill()
        }
    }
}

@MainActor
final class AliceMenuBarViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var parseResult: ParseParagraphResponse?
    @Published var errorMessage: String?
    @Published var lastCaptureMethod: CaptureMethod?
    @Published var lastLanguageHint: LanguageHint?
    @Published var shortcutConfiguration: ShortcutConfiguration
    @Published var isOCRDebugFrameEnabled: Bool
    @Published var isScreenRecordingTrusted: Bool
    @Published var isShortcutMonitorRunning: Bool = false
    @Published var lastShortcutMatchAt: Date?
    @Published var lastMonitorEvent: String = "No shortcut events yet"
    @Published var diagnosticsLogPath: String

    private let parserService: QuickSVOService
    private let captureRunner: QuickSVOCaptureRunner
    private let floatingPresenter: FloatingResultPresenting
    private let ocrDebugOverlayPresenter: OCRDebugOverlayPresenting
    private let shortcutSettingsStore: ShortcutSettingsStore
    private let diagnosticsLogger: AliceDiagnosticsLogger
    private let defaults: UserDefaults
    private var shortcutMonitor: GlobalShortcutMonitor?
    private var hasStartedShortcutMonitoring = false
    private let screenRecordingAutoPromptKey = "alice.screenRecording.autoPromptShown"

    init(
        captureProvider: TextCaptureProviding? = nil,
        floatingPresenter: FloatingResultPresenting = FloatingResultWindowManager(),
        ocrDebugOverlayPresenter: OCRDebugOverlayPresenting = OCRDebugOverlayManager(),
        shortcutSettingsStore: ShortcutSettingsStore = ShortcutSettingsStore(),
        defaults: UserDefaults = .standard
    ) {
        self.shortcutSettingsStore = shortcutSettingsStore
        self.shortcutConfiguration = shortcutSettingsStore.load()
        self.isOCRDebugFrameEnabled = shortcutSettingsStore.loadOCRDebugFrameEnabled()
        self.ocrDebugOverlayPresenter = ocrDebugOverlayPresenter
        self.diagnosticsLogger = .shared
        self.diagnosticsLogPath = diagnosticsLogger.logFilePath
        self.isScreenRecordingTrusted = CGPreflightScreenCaptureAccess()
        self.defaults = defaults

        let localParser = HeuristicSVOParser()
        self.parserService = QuickSVOService(
            sentenceSplitter: NLTokenizerSentenceSplitter(),
            localParser: localParser,
            cloudParser: CloudFallbackSVOParser(localBase: localParser),
            eventLogger: LocalEventLogger(),
            settings: QuickSVOSettings(cloudFallbackEnabled: true, confidenceThreshold: 0.55)
        )

        let resolvedCaptureProvider = captureProvider ?? OCRTextCaptureProvider(
            diagnostics: { [weak diagnosticsLogger] message in
                Task { @MainActor in
                    diagnosticsLogger?.log("capture \(message)")
                }
            }
        )
        self.captureRunner = QuickSVOCaptureRunner(captureProvider: resolvedCaptureProvider, paragraphParser: parserService)
        self.floatingPresenter = floatingPresenter

        self.inputText = "The manager approved the revised budget yesterday. She sent the summary to the team."
        diagnosticsLogger.log(
            "app initialized shortcut=\(shortcutConfiguration.displayString) " +
            "ocrDebugFrameEnabled=\(isOCRDebugFrameEnabled) " +
            "screenRecordingTrusted=\(isScreenRecordingTrusted)"
        )

        if !isScreenRecordingTrusted, shouldAutoPromptScreenRecordingPermission() {
            requestScreenRecordingPermission(reason: "startup")
            defaults.set(true, forKey: screenRecordingAutoPromptKey)
        } else if !isScreenRecordingTrusted {
            diagnosticsLogger.log("skip startup screen recording prompt: already prompted before")
        }

        startShortcutMonitoringIfNeeded()
    }

    func startShortcutMonitoringIfNeeded() {
        guard !hasStartedShortcutMonitoring else {
            diagnosticsLogger.log("startShortcutMonitoringIfNeeded ignored: already started")
            return
        }
        hasStartedShortcutMonitoring = true
        refreshPermissionStatus()

        let currentShortcut = shortcutConfiguration.normalized()
        let monitor = GlobalShortcutMonitor(
            keyCode: currentShortcut.key.keyCode,
            modifiers: currentShortcut.modifierFlags
        ) { [weak self] in
            self?.recordShortcutMatch()
            self?.captureAndParseNow(trigger: "shortcut")
        } diagnostics: { [weak self] message in
            Task { @MainActor in
                self?.handleMonitorDiagnostics(message)
            }
        }
        diagnosticsLogger.log("starting shortcut monitor shortcut=\(currentShortcut.displayString)")
        monitor.start()
        self.shortcutMonitor = monitor
        isShortcutMonitorRunning = monitor.isRunning
        diagnosticsLogger.log("shortcut monitor running=\(isShortcutMonitorRunning)")
    }

    func refreshScreenRecordingStatus() {
        isScreenRecordingTrusted = CGPreflightScreenCaptureAccess()
        diagnosticsLogger.log("refreshScreenRecordingStatus screenRecordingTrusted=\(isScreenRecordingTrusted)")
    }

    func refreshPermissionStatus() {
        refreshScreenRecordingStatus()
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            diagnosticsLogger.log("failed to construct screen recording settings URL")
            return
        }
        diagnosticsLogger.log("openScreenRecordingSettings requested")
        NSWorkspace.shared.open(url)
    }

    func requestScreenRecordingPermission(reason: String = "manual") {
        let alreadyTrusted = CGPreflightScreenCaptureAccess()
        if alreadyTrusted {
            isScreenRecordingTrusted = true
            diagnosticsLogger.log("requestScreenRecordingPermission skipped reason=\(reason) alreadyTrusted=true")
            return
        }

        let granted = CGRequestScreenCaptureAccess()
        diagnosticsLogger.log("requestScreenRecordingPermission reason=\(reason) grantedNow=\(granted)")
        refreshScreenRecordingStatus()
    }

    private func shouldAutoPromptScreenRecordingPermission() -> Bool {
        !defaults.bool(forKey: screenRecordingAutoPromptKey)
    }

    func copyDiagnosticsSummaryToPasteboard() {
        let summary = """
        shortcut=\(shortcutConfiguration.displayString)
        ocrDebugFrameEnabled=\(isOCRDebugFrameEnabled)
        screenRecordingTrusted=\(isScreenRecordingTrusted)
        monitorRunning=\(isShortcutMonitorRunning)
        lastShortcutMatch=\(display(lastShortcutMatchAt))
        lastMonitorEvent=\(lastMonitorEvent)
        logFile=\(diagnosticsLogPath)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
        diagnosticsLogger.log("copied diagnostics summary to pasteboard")
    }

    func logSnapshotForFeedback() {
        diagnosticsLogger.log(
            "snapshot shortcut=\(shortcutConfiguration.displayString) " +
            "ocrDebugFrameEnabled=\(isOCRDebugFrameEnabled) " +
            "screenRecordingTrusted=\(isScreenRecordingTrusted) " +
            "monitorRunning=\(isShortcutMonitorRunning) " +
            "lastShortcutMatch=\(display(lastShortcutMatchAt)) lastMonitorEvent=\(lastMonitorEvent)"
        )
    }

    func markMainPanelAppeared() {
        diagnosticsLogger.log("main panel appeared")
    }

    func markSettingsAppeared() {
        diagnosticsLogger.log("settings window appeared")
    }

    func updateShortcutKey(_ key: ShortcutKey) {
        var updated = shortcutConfiguration
        updated.key = key
        applyShortcutConfiguration(updated)
    }

    func updateCommandModifier(_ enabled: Bool) {
        var updated = shortcutConfiguration
        updated.command = enabled
        applyShortcutConfiguration(updated)
    }

    func updateOptionModifier(_ enabled: Bool) {
        var updated = shortcutConfiguration
        updated.option = enabled
        applyShortcutConfiguration(updated)
    }

    func updateControlModifier(_ enabled: Bool) {
        var updated = shortcutConfiguration
        updated.control = enabled
        applyShortcutConfiguration(updated)
    }

    func updateShiftModifier(_ enabled: Bool) {
        var updated = shortcutConfiguration
        updated.shift = enabled
        applyShortcutConfiguration(updated)
    }

    func updateOCRDebugFrameEnabled(_ enabled: Bool) {
        guard enabled != isOCRDebugFrameEnabled else { return }
        isOCRDebugFrameEnabled = enabled
        shortcutSettingsStore.saveOCRDebugFrameEnabled(enabled)
        diagnosticsLogger.log("ocr debug frame updated enabled=\(enabled)")
    }

    func parseFromInputText() {
        diagnosticsLogger.log("parseFromInputText length=\(inputText.count)")
        do {
            errorMessage = nil
            let result = try parserService.parseParagraph(text: inputText, sourceApp: "AliceMenuBar")
            parseResult = result

            floatingPresenter.present(
                result: result,
                captureMethod: lastCaptureMethod,
                sourceApp: "AliceMenuBar",
                at: cursorPoint()
            )
            diagnosticsLogger.log("parseFromInputText success sentences=\(result.sentences.count) latencyMs=\(result.totalLatencyMs)")
        } catch {
            parseResult = nil
            errorMessage = error.localizedDescription
            diagnosticsLogger.log("parseFromInputText failed error=\(error.localizedDescription)")
        }
    }

    func captureAndParseNow(trigger: String = "manual") {
        diagnosticsLogger.log("captureAndParseNow trigger=\(trigger)")
        refreshPermissionStatus()
        let missingPermissions = missingSystemPermissions()
        if !missingPermissions.isEmpty {
            let missing = missingPermissions.joined(separator: ", ")
            let message = "Missing permissions: \(missing). Open Settings and grant access before capture."
            parseResult = nil
            errorMessage = message
            diagnosticsLogger.log("captureAndParseNow blocked trigger=\(trigger) missingPermissions=\(missing)")
            return
        }

        let request = CaptureTextRequest(
            sourceApp: NSWorkspace.shared.frontmostApplication?.localizedName ?? "UnknownApp",
            cursorPoint: cursorPoint(),
            timestamp: Date().timeIntervalSince1970
        )

        do {
            errorMessage = nil
            let result = try captureRunner.run(request: request)
            inputText = result.capture.rawText
            parseResult = result.parse
            lastCaptureMethod = result.capture.method
            lastLanguageHint = result.capture.languageHint

            if result.capture.method == .ocr,
               isOCRDebugFrameEnabled,
               let bounds = result.capture.bounds {
                ocrDebugOverlayPresenter.present(bounds: bounds, cursorPoint: request.cursorPoint)
                diagnosticsLogger.log(
                    "ocr debug overlay shown cursor=\(Int(request.cursorPoint.x)),\(Int(request.cursorPoint.y)) " +
                    "bounds=\(Int(bounds.x)),\(Int(bounds.y)),\(Int(bounds.width))x\(Int(bounds.height))"
                )
            }

            floatingPresenter.present(
                result: result.parse,
                captureMethod: result.capture.method,
                sourceApp: request.sourceApp,
                at: request.cursorPoint
            )
            diagnosticsLogger.log(
                "captureAndParseNow success trigger=\(trigger) sourceApp=\(request.sourceApp) " +
                "captureMethod=\(result.capture.method.rawValue) textLength=\(result.capture.rawText.count) " +
                "sentences=\(result.parse.sentences.count)"
            )
        } catch {
            parseResult = nil
            errorMessage = error.localizedDescription
            diagnosticsLogger.log("captureAndParseNow failed trigger=\(trigger) error=\(error.localizedDescription)")
        }
    }

    private func recordShortcutMatch() {
        lastShortcutMatchAt = Date()
        diagnosticsLogger.log("shortcut matched at \(display(lastShortcutMatchAt))")
    }

    private func handleMonitorDiagnostics(_ message: String) {
        lastMonitorEvent = message
        diagnosticsLogger.log("monitor \(message)")
    }

    private func display(_ date: Date?) -> String {
        guard let date else { return "none" }
        return ISO8601DateFormatter().string(from: date)
    }

    private func cursorPoint() -> CursorPoint {
        let location = NSEvent.mouseLocation
        return CursorPoint(x: location.x, y: location.y)
    }

    private func applyShortcutConfiguration(_ updatedConfiguration: ShortcutConfiguration) {
        let normalized = updatedConfiguration.normalized()
        guard normalized != shortcutConfiguration else { return }

        diagnosticsLogger.log("shortcut updated from \(shortcutConfiguration.displayString) to \(normalized.displayString)")
        shortcutConfiguration = normalized
        shortcutSettingsStore.save(normalized)
        restartShortcutMonitoringIfNeeded()
    }

    private func restartShortcutMonitoringIfNeeded() {
        guard hasStartedShortcutMonitoring else { return }
        diagnosticsLogger.log("restartShortcutMonitoringIfNeeded")
        shortcutMonitor?.stop()
        shortcutMonitor = nil
        isShortcutMonitorRunning = false
        hasStartedShortcutMonitoring = false
        startShortcutMonitoringIfNeeded()
    }

    private func missingSystemPermissions() -> [String] {
        var missing: [String] = []
        if !isScreenRecordingTrusted {
            missing.append("Screen Recording")
        }
        return missing
    }
}

struct ContentView: View {
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var viewModel: AliceMenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick SVO Parse")
                .font(.headline)

            Text("Hover text in any app and press \(viewModel.shortcutConfiguration.displayString), or manually parse below.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $viewModel.inputText)
                .font(.body)
                .frame(height: 130)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )

            HStack(spacing: 8) {
                Button("Capture + Parse (\(viewModel.shortcutConfiguration.displayString))") {
                    viewModel.captureAndParseNow(trigger: "manual-button")
                }
                .buttonStyle(.borderedProminent)

                Button("Parse Input") {
                    viewModel.parseFromInputText()
                }
                .buttonStyle(.bordered)
            }

            HStack {
                Text("Shortcut: \(viewModel.shortcutConfiguration.displayString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("OCR only")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(viewModel.isOCRDebugFrameEnabled ? "DebugFrame on" : "DebugFrame off")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                Button("Open Shortcut Settings...") {
                    openSettings()
                }
                .buttonStyle(.borderless)
            }

            if !viewModel.isScreenRecordingTrusted {
                HStack(spacing: 8) {
                    Text("Screen Recording permission missing, text capture is blocked.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button("Grant...") {
                        viewModel.requestScreenRecordingPermission()
                    }
                    .buttonStyle(.borderless)
                    Button("Open Settings...") {
                        viewModel.openScreenRecordingSettings()
                    }
                    .buttonStyle(.borderless)
                }
            }

            if let method = viewModel.lastCaptureMethod {
                Text("Capture Method: \(method.rawValue.uppercased())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let language = viewModel.lastLanguageHint {
                Text("Language Hint: \(language.rawValue)")
                    .font(.caption)
                    .foregroundColor(language == .en ? .secondary : .orange)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if let parseResult = viewModel.parseResult {
                Text("Latency: \(parseResult.totalLatencyMs) ms")
                    .font(.caption)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(parseResult.sentences, id: \.index) { sentence in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Sentence \(sentence.index + 1): \(sentence.text)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Subject: \(emptyFallback(sentence.svo.subject))")
                                Text("Verb: \(emptyFallback(sentence.svo.verb))")
                                Text("Object: \(emptyFallback(sentence.svo.object))")
                                Text(String(format: "Confidence: %.2f", sentence.svo.confidence))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.bottom, 8)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .onAppear {
            viewModel.startShortcutMonitoringIfNeeded()
            viewModel.markMainPanelAppeared()
        }
    }

    private func emptyFallback(_ value: String) -> String {
        value.isEmpty ? "(none)" : value
    }
}

struct ShortcutSettingsView: View {
    @ObservedObject var viewModel: AliceMenuBarViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                GroupBox("Shortcut Settings") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Key")
                            Picker("Key", selection: keyBinding) {
                                ForEach(ShortcutKey.allCases) { key in
                                    Text(key.label).tag(key)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 100)
                        }

                        HStack(spacing: 12) {
                            Toggle("Cmd", isOn: commandBinding)
                            Toggle("Option", isOn: optionBinding)
                            Toggle("Ctrl", isOn: controlBinding)
                            Toggle("Shift", isOn: shiftBinding)
                        }
                        .toggleStyle(.checkbox)

                        Text("Current: \(viewModel.shortcutConfiguration.displayString)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }

                GroupBox("Capture Mode") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Show OCR debug frame", isOn: ocrDebugFrameEnabledBinding)
                            .toggleStyle(.switch)
                        Text("Current: OCR only")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }

                GroupBox("Diagnostics") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Screen Recording Trusted: \(viewModel.isScreenRecordingTrusted ? "Yes" : "No")")
                            .font(.caption)
                        Text("Shortcut Monitor Running: \(viewModel.isShortcutMonitorRunning ? "Yes" : "No")")
                            .font(.caption)
                        Text("Last Shortcut Match: \(displayDate(viewModel.lastShortcutMatchAt))")
                            .font(.caption)
                        Text("Last Monitor Event: \(viewModel.lastMonitorEvent)")
                            .font(.caption)
                            .lineLimit(3)
                        Text("Log File: \(viewModel.diagnosticsLogPath)")
                            .font(.caption2)
                            .textSelection(.enabled)

                        HStack(spacing: 8) {
                            Button("Refresh") {
                                viewModel.refreshPermissionStatus()
                            }
                            Button("Open Screen Recording...") {
                                viewModel.openScreenRecordingSettings()
                            }
                            Button("Request Screen Recording") {
                                viewModel.requestScreenRecordingPermission()
                            }
                        }
                        .buttonStyle(.bordered)

                        HStack(spacing: 8) {
                            Button("Copy Diagnostics") {
                                viewModel.copyDiagnosticsSummaryToPasteboard()
                            }
                            Button("Log Snapshot") {
                                viewModel.logSnapshotForFeedback()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 640, minHeight: 460)
        .onAppear {
            viewModel.markSettingsAppeared()
            viewModel.refreshPermissionStatus()
        }
    }

    private var keyBinding: Binding<ShortcutKey> {
        Binding(
            get: { viewModel.shortcutConfiguration.key },
            set: { viewModel.updateShortcutKey($0) }
        )
    }

    private var commandBinding: Binding<Bool> {
        Binding(
            get: { viewModel.shortcutConfiguration.command },
            set: { viewModel.updateCommandModifier($0) }
        )
    }

    private var optionBinding: Binding<Bool> {
        Binding(
            get: { viewModel.shortcutConfiguration.option },
            set: { viewModel.updateOptionModifier($0) }
        )
    }

    private var controlBinding: Binding<Bool> {
        Binding(
            get: { viewModel.shortcutConfiguration.control },
            set: { viewModel.updateControlModifier($0) }
        )
    }

    private var shiftBinding: Binding<Bool> {
        Binding(
            get: { viewModel.shortcutConfiguration.shift },
            set: { viewModel.updateShiftModifier($0) }
        )
    }

    private var ocrDebugFrameEnabledBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isOCRDebugFrameEnabled },
            set: { viewModel.updateOCRDebugFrameEnabled($0) }
        )
    }

    private func displayDate(_ date: Date?) -> String {
        guard let date else { return "none" }
        return ISO8601DateFormatter().string(from: date)
    }
}
