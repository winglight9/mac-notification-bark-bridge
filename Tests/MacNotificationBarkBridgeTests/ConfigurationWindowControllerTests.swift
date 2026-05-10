import Foundation
import XCTest
@testable import MacNotificationBarkBridge

@MainActor
final class ConfigurationWindowControllerTests: XCTestCase {
    func testConfigurationWindowLoadsAndSavesCommonSettingsWithoutChangingRules() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let store = ConfigurationStore(
            configurationDirectoryProvider: { rootURL },
            templateDataProvider: {
                try JSONEncoder().encode(StoredConfiguration.defaults)
            }
        )

        try store.save(
            StoredConfiguration(
                rules: [
                    StoredRoutingRule(
                        id: "rule-1",
                        name: "Primary",
                        deviceKeys: ["initial-key", "backup-key"],
                        barkBaseURL: "https://api.day.app",
                        applicationNames: ["Mail"],
                        iconURL: "https://example.com/mail.png"
                    )
                ],
                pollInterval: 6,
                dryRun: true,
                promptForAccessibility: false,
                dedupeWindow: 180,
                launchAtLogin: false,
                deviceKey: nil,
                barkBaseURL: nil,
                sourceFilter: nil
            )
        )

        var didSave = false
        let controller = ConfigurationWindowController(
            configurationStore: store,
            onSave: { didSave = true },
            onClose: {}
        )

        let loaded = try controller.currentFormConfiguration().normalized()
        XCTAssertEqual(loaded.rules?.first?.deviceKeys ?? [], ["initial-key", "backup-key"])
        XCTAssertEqual(loaded.rules?.first?.applicationNames ?? [], ["Mail"])
        XCTAssertEqual(loaded.pollInterval, 6)
        XCTAssertEqual(loaded.dryRun, true)

        controller.populateFields(
            with: StoredConfiguration(
                rules: [
                    StoredRoutingRule(
                        id: "rule-1",
                        name: "Updated",
                        deviceKeys: ["updated-key"],
                        barkBaseURL: "https://example.com",
                        applicationNames: ["Slack", "Telegram"],
                        iconURL: "https://example.com/slack.png"
                    )
                ],
                pollInterval: 3,
                dryRun: false,
                promptForAccessibility: true,
                dedupeWindow: 45,
                launchAtLogin: false,
                deviceKey: nil,
                barkBaseURL: nil,
                sourceFilter: nil
            )
        )

        try controller.saveCurrentForm()

        let saved = try store.loadStoredConfiguration().normalized()
        XCTAssertTrue(didSave)
        XCTAssertEqual(saved.rules?.first?.deviceKeys ?? [], ["initial-key", "backup-key"])
        XCTAssertEqual(saved.rules?.first?.barkBaseURL, "https://api.day.app")
        XCTAssertEqual(saved.rules?.first?.applicationNames ?? [], ["Mail"])
        XCTAssertEqual(saved.rules?.first?.iconURL, "https://example.com/mail.png")
        XCTAssertEqual(saved.pollInterval, 3)
        XCTAssertEqual(saved.promptForAccessibility, true)
        XCTAssertEqual(saved.dedupeWindow, 45)
        XCTAssertTrue(controller.statusTextForTesting.contains("已保存"))
    }

    func testConfigurationWindowPreservesRulesWhenSavingCommonSettings() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let store = ConfigurationStore(
            configurationDirectoryProvider: { rootURL },
            templateDataProvider: {
                try JSONEncoder().encode(StoredConfiguration.defaults)
            }
        )

        let original = StoredConfiguration(
            rules: [
                StoredRoutingRule(
                    id: "rule-1",
                    name: "Discord Rule",
                    deviceKeys: ["device-a"],
                    barkBaseURL: "https://bark.example.com",
                    applicationNames: ["Discord"],
                    iconURL: "https://example.com/discord.png"
                )
            ],
            pollInterval: 2,
            dryRun: false,
            promptForAccessibility: true,
            dedupeWindow: 300,
            launchAtLogin: true,
            deviceKey: nil,
            barkBaseURL: nil,
            sourceFilter: nil
        )
        try store.save(original)

        let controller = ConfigurationWindowController(
            configurationStore: store,
            onSave: {},
            onClose: {}
        )

        controller.populateFields(
            with: StoredConfiguration(
                rules: original.rules,
                pollInterval: 5,
                dryRun: true,
                promptForAccessibility: false,
                dedupeWindow: 120,
                launchAtLogin: false,
                deviceKey: nil,
                barkBaseURL: nil,
                sourceFilter: nil
            )
        )

        try controller.saveCurrentForm()

        let saved = try store.loadStoredConfiguration().normalized()
        XCTAssertEqual(saved.rules?.first?.name, "Discord Rule")
        XCTAssertEqual(saved.rules?.first?.deviceKeys ?? [], ["device-a"])
        XCTAssertEqual(saved.rules?.first?.applicationNames ?? [], ["Discord"])
        XCTAssertEqual(saved.pollInterval, 5)
        XCTAssertEqual(saved.dryRun, true)
        XCTAssertEqual(saved.promptForAccessibility, false)
        XCTAssertEqual(saved.dedupeWindow, 120)
    }
}
