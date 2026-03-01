import Foundation

public final class LocalEventLogger: EventLogging, @unchecked Sendable {
    private let fileURL: URL
    private let queue: DispatchQueue
    private let encoder: JSONEncoder

    public init(fileURL: URL = LocalEventLogger.defaultFileURL()) {
        self.fileURL = fileURL
        self.queue = DispatchQueue(label: "alice.quick-svo.events")
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.withoutEscapingSlashes]

        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func log(_ event: QuickSVOEvent) {
        let fileURL = self.fileURL
        let encoder = self.encoder

        queue.async {
            guard let data = try? encoder.encode(event),
                  var line = String(data: data, encoding: .utf8)
            else {
                return
            }

            line.append("\n")
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                _ = FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }

            guard let handle = try? FileHandle(forWritingTo: fileURL) else {
                return
            }

            defer {
                try? handle.close()
            }

            do {
                try handle.seekToEnd()
                if let output = line.data(using: .utf8) {
                    try handle.write(contentsOf: output)
                }
            } catch {
                return
            }
        }
    }

    public static func defaultFileURL() -> URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".alice", isDirectory: true)
            .appendingPathComponent("events", isDirectory: true)
            .appendingPathComponent("quick-svo.jsonl")
    }
}

public struct NoopEventLogger: EventLogging {
    public init() {}

    public func log(_ event: QuickSVOEvent) {
        _ = event
    }
}
