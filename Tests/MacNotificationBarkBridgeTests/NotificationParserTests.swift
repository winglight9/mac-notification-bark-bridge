import Foundation
import XCTest
@testable import MacNotificationBarkBridge

final class NotificationParserTests: XCTestCase {
    func testParserExtractsNotificationFromFixture() throws {
        let fixtureURL = try XCTUnwrap(Bundle.module.url(
            forResource: "sample-notification-tree",
            withExtension: "json",
            subdirectory: "Fixtures"
        ))
        let data = try Data(contentsOf: fixtureURL)
        let tree = try JSONDecoder().decode(AccessibilityNode.self, from: data)

        let parser = NotificationParser()
        let notifications = parser.parse(from: tree, sourceFilter: "messages")

        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(notifications.first?.source, "Messages")
        XCTAssertEqual(notifications.first?.title, "Alice")
        XCTAssertEqual(notifications.first?.body, "Meet at 8 PM\nBring the tickets.")
    }

    func testParserExtractsLongNotificationCenterStackUsingDescriptionAsSource() {
        let longBody = String(repeating: "Long codex reply. ", count: 40)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let tree = AccessibilityNode(
            role: "AXApplication",
            children: [
                AccessibilityNode(
                    role: "AXWindow",
                    children: [
                        AccessibilityNode(
                            role: "AXGroup",
                            subrole: "AXNotificationCenterBannerStack",
                            nodeDescription: "Codex，编写监听应用通知的Swift后台程序, \(longBody)，已叠放",
                            identifier: "codex-stack-1",
                            children: [
                                AccessibilityNode(role: "AXStaticText", value: "编写监听应用通知的Swift后台程序"),
                                AccessibilityNode(role: "AXStaticText", value: "\(longBody) "),
                                AccessibilityNode(role: "AXStaticText", value: "15分钟前"),
                            ]
                        )
                    ]
                )
            ]
        )

        let parser = NotificationParser()
        let notifications = parser.parse(from: tree, sourceFilter: nil)

        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(notifications.first?.source, "Codex")
        XCTAssertEqual(notifications.first?.title, "编写监听应用通知的Swift后台程序")
        XCTAssertEqual(notifications.first?.body, longBody)
    }

    func testParserPrefersResolvedSourceOverFallbackDuplicate() {
        let tree = AccessibilityNode(
            role: "AXApplication",
            children: [
                AccessibilityNode(
                    role: "AXWindow",
                    children: [
                        AccessibilityNode(
                            role: "AXGroup",
                            subrole: "AXNotificationCenterBanner",
                            nodeDescription: "Keka 提取完成, 提取“archive.zip”完成",
                            identifier: "keka-banner-1",
                            children: [
                                AccessibilityNode(role: "AXStaticText", value: "提取完成"),
                                AccessibilityNode(role: "AXStaticText", value: "提取“archive.zip”完成"),
                                AccessibilityNode(
                                    role: "AXGroup",
                                    children: [
                                        AccessibilityNode(role: "AXStaticText", value: "提取完成"),
                                        AccessibilityNode(role: "AXStaticText", value: "提取“archive.zip”完成"),
                                    ]
                                ),
                            ]
                        )
                    ]
                )
            ]
        )

        let parser = NotificationParser()
        let notifications = parser.parse(from: tree, sourceFilter: nil)

        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(notifications.first?.source, "Keka")
        XCTAssertEqual(notifications.first?.title, "提取完成")
        XCTAssertEqual(notifications.first?.body, "提取“archive.zip”完成")
    }

    func testParserIgnoresMenuBarContent() {
        let tree = AccessibilityNode(
            role: "AXApplication",
            children: [
                AccessibilityNode(
                    role: "AXWindow",
                    children: [
                        AccessibilityNode(
                            role: "AXMenuBar",
                            children: [
                                AccessibilityNode(role: "AXMenuBarItem", title: "Apple"),
                                AccessibilityNode(role: "AXMenuBarItem", title: "文件"),
                                AccessibilityNode(role: "AXMenuBarItem", title: "编辑"),
                            ]
                        )
                    ]
                )
            ]
        )

        let parser = NotificationParser()
        let notifications = parser.parse(from: tree, sourceFilter: nil)

        XCTAssertTrue(notifications.isEmpty)
    }

    func testParserPrefersBannerNodesWhenPresent() {
        let tree = AccessibilityNode(
            role: "AXApplication",
            children: [
                AccessibilityNode(
                    role: "AXWindow",
                    children: [
                        AccessibilityNode(
                            role: "AXGroup",
                            children: [
                                AccessibilityNode(role: "AXStaticText", value: "Apple"),
                                AccessibilityNode(role: "AXStaticText", value: "文件"),
                                AccessibilityNode(role: "AXStaticText", value: "编辑"),
                            ]
                        ),
                        AccessibilityNode(
                            role: "AXGroup",
                            subrole: "AXNotificationCenterBanner",
                            nodeDescription: "Telegram，BAGE |躺水中, 新消息",
                            identifier: "telegram-banner-1",
                            children: [
                                AccessibilityNode(role: "AXStaticText", value: "BAGE |躺水中"),
                                AccessibilityNode(role: "AXStaticText", value: "新消息"),
                            ]
                        ),
                    ]
                )
            ]
        )

        let parser = NotificationParser()
        let notifications = parser.parse(from: tree, sourceFilter: nil)

        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(notifications.first?.source, "Telegram")
        XCTAssertEqual(notifications.first?.title, "BAGE |躺水中")
        XCTAssertEqual(notifications.first?.body, "新消息")
    }
}
