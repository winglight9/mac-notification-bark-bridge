import Foundation
import XCTest
@testable import MacNotificationBarkBridge

final class BridgeLoggerTests: XCTestCase {
    func testFileBridgeLoggerWritesDailyLogsUsingChinaTimezone() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let diagnosticsStore = DiagnosticsStore(configurationDirectoryProvider: { rootURL })
        let firstDate = Date(timeIntervalSince1970: 1_778_272_200) // 2026-05-08 20:30:00 UTC
        let secondDate = Date(timeIntervalSince1970: 1_778_358_600) // 2026-05-09 20:30:00 UTC

        let firstLogger = FileBridgeLogger(
            diagnosticsStore: diagnosticsStore,
            retentionDays: 7,
            nowProvider: { firstDate }
        )
        let secondLogger = FileBridgeLogger(
            diagnosticsStore: diagnosticsStore,
            retentionDays: 7,
            nowProvider: { secondDate }
        )

        await firstLogger.log(.info, "first day")
        await secondLogger.log(.info, "second day")

        let logsDirectory = try diagnosticsStore.logsDirectoryURL()
        let fileNames = try FileManager.default.contentsOfDirectory(atPath: logsDirectory.path)
        let firstLogURL = logsDirectory.appendingPathComponent("bridge-2026-05-09.log")
        let firstLogContents = try String(contentsOf: firstLogURL, encoding: .utf8)

        XCTAssertTrue(fileNames.contains("bridge-2026-05-09.log"))
        XCTAssertTrue(fileNames.contains("bridge-2026-05-10.log"))
        XCTAssertFalse(fileNames.contains("bridge.log"))
        XCTAssertTrue(firstLogContents.contains("+08:00"))
    }

    func testFileBridgeLoggerStoresLatestAndDailySnapshots() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let diagnosticsStore = DiagnosticsStore(configurationDirectoryProvider: { rootURL })
        let now = Date(timeIntervalSince1970: 1_778_272_200) // 2026-05-08 20:30:00 UTC, China 2026-05-09
        let logger = FileBridgeLogger(
            diagnosticsStore: diagnosticsStore,
            retentionDays: 7,
            nowProvider: { now }
        )

        let root = AccessibilityNode(role: "AXApplication", title: "通知中心")
        await logger.storeSnapshot(root)

        let logsDirectory = try diagnosticsStore.logsDirectoryURL()
        let fileNames = try FileManager.default.contentsOfDirectory(atPath: logsDirectory.path)

        XCTAssertTrue(fileNames.contains("latest-tree.json"))
        XCTAssertTrue(fileNames.contains("tree-2026-05-09.json"))
    }

    func testFileBridgeLoggerRemovesExpiredDailyFilesButKeepsActiveFiles() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let diagnosticsStore = DiagnosticsStore(configurationDirectoryProvider: { rootURL })
        let logsDirectory = try diagnosticsStore.ensureLogsDirectoryExists()

        let expiredLog = logsDirectory.appendingPathComponent("bridge-2026-04-01.log")
        let expiredSnapshot = logsDirectory.appendingPathComponent("tree-2026-04-01.json")
        let activeLog = logsDirectory.appendingPathComponent("bridge-2026-05-09.log")
        let activeSnapshot = logsDirectory.appendingPathComponent("tree-2026-05-09.json")
        let latestSnapshot = logsDirectory.appendingPathComponent("latest-tree.json")

        try "old".data(using: .utf8)!.write(to: expiredLog)
        try "old".data(using: .utf8)!.write(to: expiredSnapshot)
        try "current".data(using: .utf8)!.write(to: activeLog)
        try "current".data(using: .utf8)!.write(to: activeSnapshot)
        try "current".data(using: .utf8)!.write(to: latestSnapshot)

        let oldDate = Date(timeIntervalSince1970: 1_746_662_400 - 10 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: expiredLog.path)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: expiredSnapshot.path)

        let logger = FileBridgeLogger(
            diagnosticsStore: diagnosticsStore,
            retentionDays: 7,
            nowProvider: { Date(timeIntervalSince1970: 1_746_662_400) }
        )

        await logger.log(.info, "trigger cleanup")

        XCTAssertFalse(FileManager.default.fileExists(atPath: expiredLog.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: expiredSnapshot.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: activeLog.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: activeSnapshot.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: latestSnapshot.path))
    }
}
