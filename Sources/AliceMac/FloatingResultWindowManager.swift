import AliceCore
import AppKit
import SwiftUI

@MainActor
protocol FloatingResultPresenting {
    func present(
        result: ParseParagraphResponse,
        captureMethod: CaptureMethod?,
        sourceApp: String,
        at point: CursorPoint
    )
}

@MainActor
final class FloatingResultWindowManager: FloatingResultPresenting {
    private var panel: NSPanel?
    private var autoDismissWorkItem: DispatchWorkItem?

    func present(
        result: ParseParagraphResponse,
        captureMethod: CaptureMethod?,
        sourceApp: String,
        at point: CursorPoint
    ) {
        let panel = ensurePanel()

        let cardView = FloatingResultCardView(
            sourceApp: sourceApp,
            captureMethod: captureMethod,
            parseResult: result
        )

        panel.contentView = NSHostingView(rootView: cardView)
        panel.setContentSize(NSSize(width: 560, height: 320))
        panel.setFrameOrigin(clampedOrigin(for: panel.frame.size, cursorPoint: point))
        panel.orderFrontRegardless()

        scheduleAutoDismiss()
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 320),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false

        self.panel = panel
        return panel
    }

    private func scheduleAutoDismiss() {
        autoDismissWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
        }
        autoDismissWorkItem = workItem

        DispatchQueue.main.asyncAfter(deadline: .now() + 7, execute: workItem)
    }

    private func clampedOrigin(for size: CGSize, cursorPoint: CursorPoint) -> CGPoint {
        let proposed = CGPoint(x: cursorPoint.x + 16, y: cursorPoint.y - size.height - 16)

        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: cursorPoint.x, y: cursorPoint.y)) })
            ?? NSScreen.main
        else {
            return proposed
        }

        let frame = screen.visibleFrame
        let clampedX = min(max(proposed.x, frame.minX + 8), frame.maxX - size.width - 8)
        let clampedY = min(max(proposed.y, frame.minY + 8), frame.maxY - size.height - 8)

        return CGPoint(x: clampedX, y: clampedY)
    }
}

private struct FloatingResultCardView: View {
    let sourceApp: String
    let captureMethod: CaptureMethod?
    let parseResult: ParseParagraphResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Alice Quick Parse")
                    .font(.headline)
                Spacer()
                if let captureMethod {
                    Text(captureMethod.rawValue.uppercased())
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.08))
                        .clipShape(Capsule())
                }
            }

            Text("From: \(sourceApp)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Latency: \(parseResult.totalLatencyMs) ms")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            HStack(spacing: 8) {
                roleChip(label: "Subject", color: subjectColor)
                roleChip(label: "Verb", color: verbColor)
                roleChip(label: "Object", color: objectColor)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(parseResult.sentences.prefix(4), id: \.index) { sentence in
                        VStack(alignment: .leading, spacing: 6) {
                            highlightedSentenceText(for: sentence)
                                .font(.callout)
                                .lineLimit(nil)

                            HStack(spacing: 10) {
                                roleValue(label: "S", value: fallback(sentence.svo.subject), color: subjectColor)
                                roleValue(label: "V", value: fallback(sentence.svo.verb), color: verbColor)
                                roleValue(label: "O", value: fallback(sentence.svo.object), color: objectColor)
                            }
                        }
                        .padding(.vertical, 2)
                        .padding(.bottom, 6)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 8)
        )
    }

    private func fallback(_ value: String) -> String {
        value.isEmpty ? "(none)" : value
    }

    private var subjectColor: Color { .blue }
    private var verbColor: Color { .green }
    private var objectColor: Color { .orange }

    private func roleChip(label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.16))
            .clipShape(Capsule())
    }

    private func roleValue(label: String, value: String, color: Color) -> some View {
        Text("\(label): \(value)")
            .font(.caption)
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private enum HighlightRole {
        case subject
        case verb
        case object
    }

    private struct HighlightSpan {
        let range: Range<String.Index>
        let role: HighlightRole
    }

    private func highlightedSentenceText(for sentence: ParseParagraphSentence) -> Text {
        let text = sentence.text
        let spans = makeHighlightSpans(in: text, sentence: sentence).sorted { $0.range.lowerBound < $1.range.lowerBound }

        guard !spans.isEmpty else {
            return Text(text).foregroundStyle(.primary)
        }

        var result = Text("")
        var cursor = text.startIndex

        for span in spans {
            if cursor < span.range.lowerBound {
                result = result + Text(String(text[cursor..<span.range.lowerBound])).foregroundStyle(.primary)
            }
            result = result
                + Text(String(text[span.range]))
                .foregroundStyle(color(for: span.role))
                .fontWeight(.semibold)
            cursor = span.range.upperBound
        }

        if cursor < text.endIndex {
            result = result + Text(String(text[cursor..<text.endIndex])).foregroundStyle(.primary)
        }

        return result
    }

    private func color(for role: HighlightRole) -> Color {
        switch role {
        case .subject:
            return subjectColor
        case .verb:
            return verbColor
        case .object:
            return objectColor
        }
    }

    private func makeHighlightSpans(in text: String, sentence: ParseParagraphSentence) -> [HighlightSpan] {
        var spans: [HighlightSpan] = []
        let items: [(value: String, role: HighlightRole)] = [
            (sentence.svo.subject, .subject),
            (sentence.svo.verb, .verb),
            (sentence.svo.object, .object)
        ]

        for item in items {
            guard let range = findBestRange(
                in: text,
                term: item.value,
                existing: spans.map(\.range)
            ) else {
                continue
            }
            spans.append(HighlightSpan(range: range, role: item.role))
        }

        return spans
    }

    private func findBestRange(
        in text: String,
        term rawTerm: String,
        existing: [Range<String.Index>]
    ) -> Range<String.Index>? {
        let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return nil }

        if let wholeWordRange = findMatchingRange(
            in: text,
            term: term,
            existing: existing,
            requireWordBoundary: true
        ) {
            return wholeWordRange
        }

        return findMatchingRange(
            in: text,
            term: term,
            existing: existing,
            requireWordBoundary: false
        )
    }

    private func findMatchingRange(
        in text: String,
        term: String,
        existing: [Range<String.Index>],
        requireWordBoundary: Bool
    ) -> Range<String.Index>? {
        var searchStart = text.startIndex

        while searchStart < text.endIndex,
              let range = text.range(
                  of: term,
                  options: [.caseInsensitive, .diacriticInsensitive],
                  range: searchStart..<text.endIndex
              ) {
            let overlapsExisting = existing.contains(where: { overlaps($0, range) })
            let boundaryValid = !requireWordBoundary || hasWordBoundary(in: text, range: range)
            if !overlapsExisting && boundaryValid {
                return range
            }
            searchStart = range.upperBound
        }

        return nil
    }

    private func overlaps(_ lhs: Range<String.Index>, _ rhs: Range<String.Index>) -> Bool {
        lhs.lowerBound < rhs.upperBound && rhs.lowerBound < lhs.upperBound
    }

    private func hasWordBoundary(in text: String, range: Range<String.Index>) -> Bool {
        let lowerValid: Bool = {
            guard range.lowerBound > text.startIndex else { return true }
            let before = text[text.index(before: range.lowerBound)]
            return !before.isLetter && !before.isNumber
        }()

        let upperValid: Bool = {
            guard range.upperBound < text.endIndex else { return true }
            let after = text[range.upperBound]
            return !after.isLetter && !after.isNumber
        }()

        return lowerValid && upperValid
    }
}
