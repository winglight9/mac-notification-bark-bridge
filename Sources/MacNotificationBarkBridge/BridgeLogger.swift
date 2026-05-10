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
    private let dateFormatter = ISO8601DateFormatter()
    private var retentionDays: Int
    private let fileManager: FileManager
    private let nowProvider: @Sendable () -> Date

    init(
        diagnosticsStore: DiagnosticsStore = DiagnosticsStore(),
        retentionDays: Int = 7,
        fileManager: FileManager = .default,
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.diagnosticsStore = diagnosticsStore
        self.retentionDays = max(retentionDays, 7)
        self.fileManager = fileManager
        self.nowProvider = nowProvider
        dateFormatter.timeZone = DiagnosticsStore.diagnosticsTimeZone
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func updateRetentionDays(_ days: Int) {
        retentionDays = max(days, 7)
    }

    func log(_ level: LogLevel, _ message: String) async {
        do {
            let now = nowProvider()
            try diagnosticsStore.ensureLogsDirectoryExists()
            try cleanupExpiredDiagnostics(now: now)
            let fileURL = try diagnosticsStore.logFileURL(for: now)
            try appendLine(
                "[\(dateFormatter.string(from: now))] [\(level.rawValue)] \(message)\n",
                to: fileURL
            )
        } catch {
            fputs("log-error: \(error.localizedDescription)\n", stderr)
        }
    }

    func storeSnapshot(_ root: AccessibilityNode) async {
        do {
            let now = nowProvider()
            let snapshotURL = try diagnosticsStore.latestSnapshotURL()
            try diagnosticsStore.ensureLogsDirectoryExists()
            try cleanupExpiredDiagnostics(now: now)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(root)
            try data.write(to: snapshotURL, options: .atomic)

            let dailySnapshotURL = try diagnosticsStore.dailySnapshotURL(for: now)
            try data.write(to: dailySnapshotURL, options: .atomic)
        } catch {
            fputs("snapshot-error: \(error.localizedDescription)\n", stderr)
        }
    }

    private func appendLine(_ line: String, to fileURL: URL) throws {
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

    private func cleanupExpiredDiagnostics(now: Date) throws {
        let expirationInterval = TimeInterval(retentionDays) * 24 * 60 * 60
        let cutoffDate = now.addingTimeInterval(-expirationInterval)

        for fileURL in try diagnosticsStore.cleanupCandidateFileURLs() {
            let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            guard let modificationDate = values.contentModificationDate else {
                continue
            }
            guard modificationDate < cutoffDate else {
                continue
            }
            try fileManager.removeItem(at: fileURL)
        }
    }
}
