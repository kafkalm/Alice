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

    private let parserService: QuickSVOService
    private let captureRunner: QuickSVOCaptureRunner
    private var shortcutMonitor: GlobalShortcutMonitor?
    private var hasStartedShortcutMonitoring = false

    init(captureProvider: TextCaptureProviding = AccessibilityFirstTextCaptureProvider()) {
        let localParser = HeuristicSVOParser()
        self.parserService = QuickSVOService(
            sentenceSplitter: NLTokenizerSentenceSplitter(),
            localParser: localParser,
            cloudParser: CloudFallbackSVOParser(localBase: localParser),
            eventLogger: LocalEventLogger(),
            settings: QuickSVOSettings(cloudFallbackEnabled: true, confidenceThreshold: 0.55)
        )
        self.captureRunner = QuickSVOCaptureRunner(captureProvider: captureProvider, paragraphParser: parserService)

        self.inputText = "The manager approved the revised budget yesterday. She sent the summary to the team."
    }

    func startShortcutMonitoringIfNeeded() {
        guard !hasStartedShortcutMonitoring else { return }
        hasStartedShortcutMonitoring = true

        let monitor = GlobalShortcutMonitor { [weak self] in
            self?.captureAndParseNow()
        }
        monitor.start()
        self.shortcutMonitor = monitor
    }

    func parseFromInputText() {
        do {
            errorMessage = nil
            parseResult = try parserService.parseParagraph(text: inputText, sourceApp: "AliceMenuBar")
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
        } catch {
            parseResult = nil
            errorMessage = error.localizedDescription
        }
    }

    private func cursorPoint() -> CursorPoint {
        let location = NSEvent.mouseLocation
        return CursorPoint(x: location.x, y: location.y)
    }
}

struct ContentView: View {
    @ObservedObject var viewModel: AliceMenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick SVO Parse")
                .font(.headline)

            Text("Hover text in any app and press Command + Shift + A, or manually parse below.")
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
                Button("Capture + Parse (⌘⇧A)") {
                    viewModel.captureAndParseNow()
                }
                .buttonStyle(.borderedProminent)

                Button("Parse Input") {
                    viewModel.parseFromInputText()
                }
                .buttonStyle(.bordered)
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
}
