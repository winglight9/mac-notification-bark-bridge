import Foundation

protocol BridgeLogging: Sendable {
    func log(_ level: LogLevel, _ message: String) async
    func storeSnapshot(_ root: AccessibilityNode) async
}

enum LogLevel: String, Sendable {
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

struct NoopBridgeLogger: BridgeLogging {
    func log(_ level: LogLevel, _ message: String) async {}
    func storeSnapshot(_ root: AccessibilityNode) async {}
}

actor FileBridgeLogger: BridgeLogging {
    private let diagnosticsStore: DiagnosticsStore
    private let maxFileSizeBytes = 512_000
    private let dateFormatter = ISO8601DateFormatter()

    init(diagnosticsStore: DiagnosticsStore = DiagnosticsStore()) {
        self.diagnosticsStore = diagnosticsStore
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func log(_ level: LogLevel, _ message: String) async {
        do {
            let fileURL = try diagnosticsStore.logFileURL()
            try diagnosticsStore.ensureLogsDirectoryExists()
            try rotateIfNeeded(fileURL: fileURL)
            try appendLine(
                "[\(dateFormatter.string(from: Date()))] [\(level.rawValue)] \(message)\n",
                to: fileURL
            )
        } catch {
            fputs("log-error: \(error.localizedDescription)\n", stderr)
        }
    }

    func storeSnapshot(_ root: AccessibilityNode) async {
        do {
            let snapshotURL = try diagnosticsStore.latestSnapshotURL()
            try diagnosticsStore.ensureLogsDirectoryExists()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(root)
            try data.write(to: snapshotURL, options: .atomic)
        } catch {
            fputs("snapshot-error: \(error.localizedDescription)\n", stderr)
        }
    }

    private func appendLine(_ line: String, to fileURL: URL) throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: Data())
        }

        let handle = try FileHandle(forWritingTo: fileURL)
        defer {
            try? handle.close()
        }

        try handle.seekToEnd()
        if let data = line.data(using: .utf8) {
            try handle.write(contentsOf: data)
        }
    }

    private func rotateIfNeeded(fileURL: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        let fileSize = attributes[.size] as? NSNumber
        guard let bytes = fileSize?.intValue, bytes >= maxFileSizeBytes else {
            return
        }

        let archivedURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("bridge.previous.log", isDirectory: false)
        if fileManager.fileExists(atPath: archivedURL.path) {
            try fileManager.removeItem(at: archivedURL)
        }
        try fileManager.moveItem(at: fileURL, to: archivedURL)
    }
}
