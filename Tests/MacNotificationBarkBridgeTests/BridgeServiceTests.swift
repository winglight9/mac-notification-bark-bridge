import Foundation
import XCTest
@testable import MacNotificationBarkBridge

actor TestLogger: BridgeLogging {
    private(set) var entries: [String] = []

    func log(_ level: LogLevel, _ message: String) async {
        entries.append("[\(level.rawValue)] \(message)")
    }

    func storeSnapshot(_ root: AccessibilityNode) async {}

    func messages() -> [String] {
        entries
    }
}

final class BridgeServiceTests: XCTestCase {
    func testBridgeServiceDryRunProcessesFixtureWithoutNetwork() async throws {
        let fixtureURL = try XCTUnwrap(Bundle.module.url(
            forResource: "sample-notification-tree",
            withExtension: "json",
            subdirectory: "Fixtures"
        ))

        let configuration = AppConfiguration(
            rules: [
                NotificationRoutingRule(
                    id: "rule-1",
                    name: "Messages",
                    barkBaseURL: URL(string: "https://api.day.app")!,
                    deviceKeys: ["test"],
                    applicationNames: ["Messages"],
                    iconURL: nil
                )
            ],
            pollInterval: 1,
            dryRun: true,
            runOnce: true,
            dumpTree: false,
            fixturePath: fixtureURL.path,
            promptForAccessibility: false,
            dedupeWindow: 300,
            launchAtLogin: false,
            diagnosticsRetentionDays: 7,
            idleScreenDimmingEnabled: false,
            idleScreenDimmingDelay: 600,
            idleScreenDimmingOpacity: 1.0
        )

        let barkClient = BarkClient(sender: { _ in
            XCTFail("dry-run path should not call Bark")
            let response = HTTPURLResponse(
                url: URL(string: "https://api.day.app/test")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        })

        var service = BridgeService(
            configuration: configuration,
            snapshotProvider: FixtureSnapshotProvider(path: fixtureURL.path),
            barkClient: barkClient
        )

        let notifications = try await service.runOnce()
        XCTAssertEqual(notifications.count, 1)
    }

    func testBridgeServiceLogsFullNotificationBodyWithoutRedaction() async throws {
        let fixtureURL = try XCTUnwrap(Bundle.module.url(
            forResource: "sample-notification-tree",
            withExtension: "json",
            subdirectory: "Fixtures"
        ))

        let configuration = AppConfiguration(
            rules: [
                NotificationRoutingRule(
                    id: "rule-1",
                    name: "Messages",
                    barkBaseURL: URL(string: "https://api.day.app")!,
                    deviceKeys: ["test"],
                    applicationNames: ["Messages"],
                    iconURL: nil
                )
            ],
            pollInterval: 1,
            dryRun: true,
            runOnce: true,
            dumpTree: false,
            fixturePath: fixtureURL.path,
            promptForAccessibility: false,
            dedupeWindow: 300,
            launchAtLogin: false,
            diagnosticsRetentionDays: 7,
            idleScreenDimmingEnabled: false,
            idleScreenDimmingDelay: 600,
            idleScreenDimmingOpacity: 1.0
        )

        let logger = TestLogger()
        let barkClient = BarkClient(sender: { _ in
            XCTFail("dry-run path should not call Bark")
            let response = HTTPURLResponse(
                url: URL(string: "https://api.day.app/test")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        })

        var service = BridgeService(
            configuration: configuration,
            snapshotProvider: FixtureSnapshotProvider(path: fixtureURL.path),
            barkClient: barkClient,
            logger: logger
        )

        _ = try await service.runOnce()

        let messages = await logger.messages()
        let notificationLog = try XCTUnwrap(messages.first(where: { $0.contains("scan.notification") }))
        XCTAssertTrue(notificationLog.contains("source=\"Messages\""))
        XCTAssertTrue(notificationLog.contains("title=\"Alice\""))
        XCTAssertTrue(notificationLog.contains("body=\"Meet at 8 PM\\nBring the tickets.\""))
        XCTAssertFalse(notificationLog.contains("bodyRedacted=true"))
        XCTAssertFalse(notificationLog.contains("bodyLength="))
    }
}
