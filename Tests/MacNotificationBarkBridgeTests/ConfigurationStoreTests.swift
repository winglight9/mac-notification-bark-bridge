import Foundation
import XCTest
@testable import MacNotificationBarkBridge

final class ConfigurationStoreTests: XCTestCase {
    func testConfigurationStoreCreatesTemplateAndLoadsResolvedConfiguration() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let store = ConfigurationStore(
            configurationDirectoryProvider: { rootURL },
            templateDataProvider: {
                """
                {
                  "rules": [
                    {
                      "id": "rule-1",
                      "name": "Primary",
                      "deviceKeys": ["abc123", "xyz789"],
                      "barkBaseURL": "https://api.day.app",
                      "applicationNames": ["Messages", "Telegram"],
                      "iconURL": "https://example.com/icon.png"
                    }
                  ],
                  "pollInterval": 5,
                  "dedupeWindow": 90,
                  "dryRun": true,
                  "promptForAccessibility": false,
                  "launchAtLogin": true
                }
                """.data(using: .utf8)!
            }
        )

        let fileURL = try store.ensureConfigurationFileExists()
        let configuration = try store.load()

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(configuration.rules.count, 1)
        XCTAssertEqual(configuration.rules[0].deviceKeys, ["abc123", "xyz789"])
        XCTAssertEqual(configuration.rules[0].applicationNames, ["Messages", "Telegram"])
        XCTAssertEqual(configuration.rules[0].iconURL?.absoluteString, "https://example.com/icon.png")
        XCTAssertEqual(configuration.pollInterval, 5)
        XCTAssertEqual(configuration.dedupeWindow, 90)
        XCTAssertTrue(configuration.dryRun)
        XCTAssertFalse(configuration.promptForAccessibility)
        XCTAssertTrue(configuration.launchAtLogin)
        XCTAssertEqual(configuration.diagnosticsRetentionDays, 7)
    }

    func testConfigurationStoreMigratesLegacySingleRuleConfiguration() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let store = ConfigurationStore(
            configurationDirectoryProvider: { rootURL },
            templateDataProvider: {
                """
                {
                  "deviceKey": "abc123",
                  "barkBaseURL": "https://api.day.app",
                  "sourceFilter": "Mail, Discord",
                  "pollInterval": 4,
                  "dedupeWindow": 120,
                  "dryRun": true,
                  "promptForAccessibility": false
                }
                """.data(using: .utf8)!
            }
        )

        let configuration = try store.load()
        XCTAssertEqual(configuration.rules.count, 1)
        XCTAssertEqual(configuration.rules[0].deviceKeys, ["abc123"])
        XCTAssertEqual(configuration.rules[0].applicationNames, ["Mail", "Discord"])
        XCTAssertEqual(configuration.pollInterval, 4)
        XCTAssertEqual(configuration.dedupeWindow, 120)
        XCTAssertTrue(configuration.dryRun)
        XCTAssertFalse(configuration.promptForAccessibility)
        XCTAssertEqual(configuration.diagnosticsRetentionDays, 7)
    }

    func testConfigurationStoreLoadsCustomDiagnosticsRetentionDays() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let store = ConfigurationStore(
            configurationDirectoryProvider: { rootURL },
            templateDataProvider: {
                """
                {
                  "rules": [
                    {
                      "id": "rule-1",
                      "name": "Primary",
                      "deviceKeys": ["abc123"],
                      "barkBaseURL": "https://api.day.app",
                      "applicationNames": ["Discord"]
                    }
                  ],
                  "diagnosticsRetentionDays": 14
                }
                """.data(using: .utf8)!
            }
        )

        let configuration = try store.load()
        XCTAssertEqual(configuration.diagnosticsRetentionDays, 14)
    }

    func testConfigurationStoreRejectsDiagnosticsRetentionBelowSevenDays() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let store = ConfigurationStore(
            configurationDirectoryProvider: { rootURL },
            templateDataProvider: {
                """
                {
                  "rules": [
                    {
                      "id": "rule-1",
                      "name": "Primary",
                      "deviceKeys": ["abc123"],
                      "barkBaseURL": "https://api.day.app",
                      "applicationNames": ["Discord"]
                    }
                  ],
                  "diagnosticsRetentionDays": 6
                }
                """.data(using: .utf8)!
            }
        )

        XCTAssertThrowsError(try store.load()) { error in
            guard case let BridgeError.invalidFieldValue(field, reason) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(field, "诊断保留天数")
            XCTAssertEqual(reason, "至少保留 7 天。")
        }
    }
}
