import Foundation
import Testing
@testable import MacNotificationBarkBridge

@Test func bridgeServiceDryRunProcessesFixtureWithoutNetwork() async throws {
    let fixtureURL = try #require(Bundle.module.url(
        forResource: "sample-notification-tree",
        withExtension: "json",
        subdirectory: "Fixtures"
    ))

    let configuration = AppConfiguration(
        deviceKey: "test",
        barkBaseURL: URL(string: "https://api.day.app")!,
        sourceFilter: "messages",
        pollInterval: 1,
        dryRun: true,
        runOnce: true,
        dumpTree: false,
        fixturePath: fixtureURL.path,
        promptForAccessibility: false,
        dedupeWindow: 300
    )

    let barkClient = BarkClient(
        baseURL: configuration.barkBaseURL,
        deviceKey: configuration.deviceKey,
        sender: { _ in
            Issue.record("dry-run path should not call Bark")
            let response = HTTPURLResponse(
                url: URL(string: "https://api.day.app/test")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        }
    )

    var service = BridgeService(
        configuration: configuration,
        snapshotProvider: FixtureSnapshotProvider(path: fixtureURL.path),
        barkClient: barkClient
    )

    let notifications = try await service.runOnce()
    #expect(notifications.count == 1)
}
