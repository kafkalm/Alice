import AliceCore
import AppKit
@preconcurrency import ApplicationServices
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
final class AliceMenuBarViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var parseResult: ParseParagraphResponse?
    @Published var errorMessage: String?
    @Published var lastCaptureMethod: CaptureMethod?
    @Published var lastLanguageHint: LanguageHint?
    @Published var shortcutConfiguration: ShortcutConfiguration
    @Published var isAccessibilityTrusted: Bool
    @Published var isShortcutMonitorRunning: Bool = false
    @Published var lastShortcutMatchAt: Date?
    @Published var lastMonitorEvent: String = "No shortcut events yet"
    @Published var diagnosticsLogPath: String

    private let parserService: QuickSVOService
    private let captureRunner: QuickSVOCaptureRunner
    private let floatingPresenter: FloatingResultPresenting
    private let shortcutSettingsStore: ShortcutSettingsStore
    private let diagnosticsLogger: AliceDiagnosticsLogger
    private var shortcutMonitor: GlobalShortcutMonitor?
    private var hasStartedShortcutMonitoring = false

    init(
        captureProvider: TextCaptureProviding? = nil,
        floatingPresenter: FloatingResultPresenting = FloatingResultWindowManager(),
        shortcutSettingsStore: ShortcutSettingsStore = ShortcutSettingsStore()
    ) {
        self.shortcutSettingsStore = shortcutSettingsStore
        self.shortcutConfiguration = shortcutSettingsStore.load()
        self.diagnosticsLogger = .shared
        self.diagnosticsLogPath = diagnosticsLogger.logFilePath
        self.isAccessibilityTrusted = AXIsProcessTrusted()

        let localParser = HeuristicSVOParser()
        self.parserService = QuickSVOService(
            sentenceSplitter: NLTokenizerSentenceSplitter(),
            localParser: localParser,
            cloudParser: CloudFallbackSVOParser(localBase: localParser),
            eventLogger: LocalEventLogger(),
            settings: QuickSVOSettings(cloudFallbackEnabled: true, confidenceThreshold: 0.55)
        )

        let resolvedCaptureProvider = captureProvider ?? AccessibilityFirstTextCaptureProvider(
            diagnostics: { [weak diagnosticsLogger] message in
                Task { @MainActor in
                    diagnosticsLogger?.log("capture \(message)")
                }
            }
        )
        self.captureRunner = QuickSVOCaptureRunner(captureProvider: resolvedCaptureProvider, paragraphParser: parserService)
        self.floatingPresenter = floatingPresenter

        self.inputText = "The manager approved the revised budget yesterday. She sent the summary to the team."
        diagnosticsLogger.log("app initialized shortcut=\(shortcutConfiguration.displayString) accessibilityTrusted=\(isAccessibilityTrusted)")
        if !isAccessibilityTrusted {
            triggerAccessibilityPermissionPrompt(reason: "startup")
        }
        startShortcutMonitoringIfNeeded()
    }

    func startShortcutMonitoringIfNeeded() {
        guard !hasStartedShortcutMonitoring else {
            diagnosticsLogger.log("startShortcutMonitoringIfNeeded ignored: already started")
            return
        }
        hasStartedShortcutMonitoring = true
        refreshAccessibilityStatus()

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
        if !isAccessibilityTrusted {
            diagnosticsLogger.log("accessibility permission missing; global shortcut may not fire outside app")
            if errorMessage == nil {
                errorMessage = "Global shortcut may not work in other apps until Accessibility permission is granted."
            }
        }
        monitor.start()
        self.shortcutMonitor = monitor
        isShortcutMonitorRunning = monitor.isRunning
        diagnosticsLogger.log("shortcut monitor running=\(isShortcutMonitorRunning)")
    }

    func refreshAccessibilityStatus() {
        isAccessibilityTrusted = AXIsProcessTrusted()
        diagnosticsLogger.log("refreshAccessibilityStatus accessibilityTrusted=\(isAccessibilityTrusted)")
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            diagnosticsLogger.log("failed to construct accessibility settings URL")
            return
        }
        diagnosticsLogger.log("openAccessibilitySettings requested")
        NSWorkspace.shared.open(url)
    }

    func requestAccessibilityPermission() {
        triggerAccessibilityPermissionPrompt(reason: "manual")
    }

    private func triggerAccessibilityPermissionPrompt(reason: String) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        diagnosticsLogger.log("requestAccessibilityPermission reason=\(reason) trustedNow=\(trusted)")
        refreshAccessibilityStatus()
    }

    func copyDiagnosticsSummaryToPasteboard() {
        let summary = """
        shortcut=\(shortcutConfiguration.displayString)
        accessibilityTrusted=\(isAccessibilityTrusted)
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
            "accessibilityTrusted=\(isAccessibilityTrusted) monitorRunning=\(isShortcutMonitorRunning) " +
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

                Spacer(minLength: 12)

                Button("Open Shortcut Settings...") {
                    openSettings()
                }
                .buttonStyle(.borderless)
            }

            if !viewModel.isAccessibilityTrusted {
                HStack(spacing: 8) {
                    Text("Accessibility permission missing, global shortcut may not work.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button("Grant...") {
                        viewModel.requestAccessibilityPermission()
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

            GroupBox("Diagnostics") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Accessibility Trusted: \(viewModel.isAccessibilityTrusted ? "Yes" : "No")")
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
                            viewModel.refreshAccessibilityStatus()
                        }
                        Button("Open Accessibility...") {
                            viewModel.openAccessibilitySettings()
                        }
                        Button("Request Permission") {
                            viewModel.requestAccessibilityPermission()
                        }
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
        .onAppear {
            viewModel.markSettingsAppeared()
            viewModel.refreshAccessibilityStatus()
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

    private func displayDate(_ date: Date?) -> String {
        guard let date else { return "none" }
        return ISO8601DateFormatter().string(from: date)
    }
}
