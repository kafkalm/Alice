import AliceCore
import SwiftUI

@MainActor
final class AliceMenuBarViewModel: ObservableObject {
    @Published var inputText: String = "The manager approved the revised budget yesterday. She sent the summary to the team."
    @Published var parseResult: ParseParagraphResponse?
    @Published var errorMessage: String?

    private let service: QuickSVOService

    init() {
        let localParser = HeuristicSVOParser()
        self.service = QuickSVOService(
            sentenceSplitter: NLTokenizerSentenceSplitter(),
            localParser: localParser,
            cloudParser: CloudFallbackSVOParser(localBase: localParser),
            eventLogger: LocalEventLogger(),
            settings: QuickSVOSettings(cloudFallbackEnabled: true, confidenceThreshold: 0.55)
        )
    }

    func parseNow() {
        do {
            errorMessage = nil
            parseResult = try service.parseParagraph(text: inputText, sourceApp: "AliceMenuBar")
        } catch {
            parseResult = nil
            errorMessage = error.localizedDescription
        }
    }
}

struct ContentView: View {
    @ObservedObject var viewModel: AliceMenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick SVO Parse")
                .font(.headline)

            Text("Paste or type an English paragraph, then parse sentence-by-sentence.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $viewModel.inputText)
                .font(.body)
                .frame(height: 130)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )

            Button("Parse") {
                viewModel.parseNow()
            }
            .buttonStyle(.borderedProminent)

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
    }

    private func emptyFallback(_ value: String) -> String {
        value.isEmpty ? "(none)" : value
    }
}
