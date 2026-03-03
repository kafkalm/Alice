import AliceCore
import AppKit
import SwiftUI

@MainActor
final class AliceMenuBarViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var parseResult: ParseParagraphResponse?
    @Published var errorMessage: String?
    @Published var lastCaptureMethod: CaptureMethod?
    @Published var lastLanguageHint: LanguageHint?
    @Published var shortcutConfiguration: ShortcutConfiguration

    private let parserService: QuickSVOService
    private let captureRunner: QuickSVOCaptureRunner
    private let floatingPresenter: FloatingResultPresenting
    private let shortcutSettingsStore: ShortcutSettingsStore
    private var shortcutMonitor: GlobalShortcutMonitor?
    private var hasStartedShortcutMonitoring = false

    init(
        captureProvider: TextCaptureProviding = AccessibilityFirstTextCaptureProvider(),
        floatingPresenter: FloatingResultPresenting = FloatingResultWindowManager(),
        shortcutSettingsStore: ShortcutSettingsStore = ShortcutSettingsStore()
    ) {
        self.shortcutSettingsStore = shortcutSettingsStore
        self.shortcutConfiguration = shortcutSettingsStore.load()

        let localParser = HeuristicSVOParser()
        self.parserService = QuickSVOService(
            sentenceSplitter: NLTokenizerSentenceSplitter(),
            localParser: localParser,
            cloudParser: CloudFallbackSVOParser(localBase: localParser),
            eventLogger: LocalEventLogger(),
            settings: QuickSVOSettings(cloudFallbackEnabled: true, confidenceThreshold: 0.55)
        )
        self.captureRunner = QuickSVOCaptureRunner(captureProvider: captureProvider, paragraphParser: parserService)
        self.floatingPresenter = floatingPresenter

        self.inputText = "The manager approved the revised budget yesterday. She sent the summary to the team."
    }

    func startShortcutMonitoringIfNeeded() {
        guard !hasStartedShortcutMonitoring else { return }
        hasStartedShortcutMonitoring = true

        let currentShortcut = shortcutConfiguration.normalized()
        let monitor = GlobalShortcutMonitor(
            keyCode: currentShortcut.key.keyCode,
            modifiers: currentShortcut.modifierFlags
        ) { [weak self] in
            self?.captureAndParseNow()
        }
        monitor.start()
        self.shortcutMonitor = monitor
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
        } catch {
            parseResult = nil
            errorMessage = error.localizedDescription
        }
    }

    func captureAndParseNow() {
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
        } catch {
            parseResult = nil
            errorMessage = error.localizedDescription
        }
    }

    private func cursorPoint() -> CursorPoint {
        let location = NSEvent.mouseLocation
        return CursorPoint(x: location.x, y: location.y)
    }

    private func applyShortcutConfiguration(_ updatedConfiguration: ShortcutConfiguration) {
        let normalized = updatedConfiguration.normalized()
        guard normalized != shortcutConfiguration else { return }

        shortcutConfiguration = normalized
        shortcutSettingsStore.save(normalized)
        restartShortcutMonitoringIfNeeded()
    }

    private func restartShortcutMonitoringIfNeeded() {
        guard hasStartedShortcutMonitoring else { return }
        shortcutMonitor?.stop()
        shortcutMonitor = nil
        hasStartedShortcutMonitoring = false
        startShortcutMonitoringIfNeeded()
    }
}

struct ContentView: View {
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
                    viewModel.captureAndParseNow()
                }
                .buttonStyle(.borderedProminent)

                Button("Parse Input") {
                    viewModel.parseFromInputText()
                }
                .buttonStyle(.bordered)
            }

            GroupBox("Shortcut Settings") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Key")
                        Picker("Key", selection: keyBinding) {
                            ForEach(ShortcutKey.allCases) { key in
                                Text(key.label).tag(key)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 90)
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
        }
    }

    private func emptyFallback(_ value: String) -> String {
        value.isEmpty ? "(none)" : value
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
}
