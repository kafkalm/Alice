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
        panel.setContentSize(NSSize(width: 380, height: 280))
        panel.setFrameOrigin(clampedOrigin(for: panel.frame.size, cursorPoint: point))
        panel.orderFrontRegardless()

        scheduleAutoDismiss()
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 280),
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

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(parseResult.sentences.prefix(4), id: \.index) { sentence in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("S: \(fallback(sentence.svo.subject))")
                            Text("V: \(fallback(sentence.svo.verb))")
                            Text("O: \(fallback(sentence.svo.object))")
                        }
                        .font(.caption)
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
}
