import Foundation

struct DiagnosticsStore: Sendable {
    static let diagnosticsTimeZone = TimeZone(identifier: "Asia/Shanghai")
        ?? TimeZone(secondsFromGMT: 8 * 60 * 60)
        ?? .current

    let configurationDirectoryProvider: @Sendable () throws -> URL

    init(
        configurationDirectoryProvider: @escaping @Sendable () throws -> URL = ConfigurationStore.defaultConfigurationDirectory
    ) {
        self.configurationDirectoryProvider = configurationDirectoryProvider
    }

    func configurationDirectoryURL() throws -> URL {
        try configurationDirectoryProvider()
    }

    func logsDirectoryURL() throws -> URL {
        try configurationDirectoryURL()
            .appendingPathComponent("Logs", isDirectory: true)
    }

    func logFileURL(for date: Date = Date()) throws -> URL {
        let fileName = "bridge-\(Self.dayString(from: date)).log"
        return try logsDirectoryURL().appendingPathComponent(fileName, isDirectory: false)
    }

    func latestSnapshotURL() throws -> URL {
        try logsDirectoryURL().appendingPathComponent("latest-tree.json", isDirectory: false)
    }

    func dailySnapshotURL(for date: Date = Date()) throws -> URL {
        let fileName = "tree-\(Self.dayString(from: date)).json"
        return try logsDirectoryURL().appendingPathComponent(fileName, isDirectory: false)
    }

    func cleanupCandidateFileURLs() throws -> [URL] {
        let directoryURL = try logsDirectoryURL()
        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        return fileURLs.filter { url in
            let name = url.lastPathComponent
            return name.hasPrefix("bridge-") || name.hasPrefix("tree-")
        }
    }

    @discardableResult
    func ensureLogsDirectoryExists() throws -> URL {
        let directoryURL = try logsDirectoryURL()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        return directoryURL
    }

    private static func dayString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = diagnosticsTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
