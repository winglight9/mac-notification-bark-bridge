import Foundation

struct DiagnosticsStore: Sendable {
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

    func logFileURL() throws -> URL {
        try logsDirectoryURL().appendingPathComponent("bridge.log", isDirectory: false)
    }

    func latestSnapshotURL() throws -> URL {
        try logsDirectoryURL().appendingPathComponent("latest-tree.json", isDirectory: false)
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
}
