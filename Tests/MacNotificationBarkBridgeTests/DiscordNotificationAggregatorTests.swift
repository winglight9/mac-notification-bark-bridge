import Foundation
import XCTest
@testable import MacNotificationBarkBridge

final class DiscordNotificationAggregatorTests: XCTestCase {
    func testParsesDiscordChannelFromNotificationTitle() throws {
        let notification = ForwardedNotification(
            source: "Discord ⁨站长转发1⁩ (⁨#猫姐聊天区⁩",
            title: "⁨站长转发1⁩ (⁨#猫姐聊天区⁩, ⁨猫姐会员频道⁩)",
            body: "**Dennis**: 所以就保留仓位",
            identifier: "n1"
        )

        let parsed = try XCTUnwrap(ParsedDiscordNotification.parse(notification))
        XCTAssertEqual(parsed.author, "Dennis")
        XCTAssertEqual(parsed.channel, "#猫姐聊天区")
        XCTAssertEqual(parsed.server, "猫姐会员频道")
        XCTAssertEqual(parsed.message, "**Dennis**: 所以就保留仓位")
    }

    func testRelayAuthorUsesForwardedSpeakerFromBody() throws {
        let notification = ForwardedNotification(
            source: "Discord ⁨站长转发1⁩ (⁨#会员聊天区⁩",
            title: "⁨站长转发1⁩ (⁨#会员聊天区⁩, ⁨天哥复利之道会员⁩)",
            body: "**summer**: IPO定价为每股115-125",
            identifier: "relay-1"
        )

        let parsed = try XCTUnwrap(ParsedDiscordNotification.parse(notification))
        XCTAssertEqual(parsed.author, "summer")
    }

    func testRelayReplyUsesLastForwardedSpeakerFromBody() throws {
        let notification = ForwardedNotification(
            source: "Discord ⁨站长转发1⁩ (⁨#猫姐聊天区⁩",
            title: "⁨站长转发1⁩ (⁨#猫姐聊天区⁩, ⁨猫姐会员频道⁩)",
            body: "↪️ 回复 Fan: 今天关注到一个MRAM **Vicky**: 一天60% 牛了",
            identifier: "relay-2"
        )

        let parsed = try XCTUnwrap(ParsedDiscordNotification.parse(notification))
        XCTAssertEqual(parsed.author, "Vicky")
    }

    func testPreservesAuthorParenthesesAndParsesTrailingDiscordContext() throws {
        let notification = ForwardedNotification(
            source: "Discord ⁨妞妞帮之大猛箭的爹(RKLB 200! NOK 100!)⁩ (⁨#🔒｜成员策略交流⁩",
            title: "⁨妞妞帮之大猛箭的爹(RKLB 200! NOK 100!)⁩ (⁨#🔒｜成员策略交流⁩, ⁨🔴【深度研究专区】⁩)",
            body: "认知不同",
            identifier: "member-name-parentheses"
        )

        let parsed = try XCTUnwrap(ParsedDiscordNotification.parse(notification))
        XCTAssertEqual(parsed.author, "妞妞帮之大猛箭的爹(RKLB 200! NOK 100!)")
        XCTAssertEqual(parsed.channel, "#🔒｜成员策略交流")
        XCTAssertEqual(parsed.server, "🔴【深度研究专区】")
    }

    func testSameChannelNameInDifferentServersDoesNotMix() throws {
        var aggregator = DiscordChannelAggregator(window: 300, maxSummaryCharacters: 1_000)
        let destination = BarkPushDestination(
            baseURL: URL(string: "https://api.day.app")!,
            deviceKey: "abc123",
            iconURL: nil
        )

        let first = ParsedDiscordNotification.parse(
            ForwardedNotification(
                source: "Discord 站长转发1 (#频道",
                title: "站长转发1 (#频道, 服务器A)",
                body: "**A**: 第一条",
                identifier: "server-a"
            )
        )
        let second = ParsedDiscordNotification.parse(
            ForwardedNotification(
                source: "Discord 站长转发1 (#频道",
                title: "站长转发1 (#频道, 服务器B)",
                body: "**B**: 第二条",
                identifier: "server-b"
            )
        )

        _ = aggregator.enqueue(
            try XCTUnwrap(first),
            destinations: [destination],
            now: Date(timeIntervalSince1970: 0)
        )
        _ = aggregator.enqueue(
            try XCTUnwrap(second),
            destinations: [destination],
            now: Date(timeIntervalSince1970: 60)
        )

        let summaries = aggregator.flushDue(now: Date(timeIntervalSince1970: 361))
        XCTAssertEqual(summaries.count, 2)
        XCTAssertTrue(summaries.map(\.notification.title).contains("站长转发1 (#频道, 服务器A)"))
        XCTAssertTrue(summaries.map(\.notification.title).contains("站长转发1 (#频道, 服务器B)"))
    }

    func testMessagesWaitForWindowAndThenSummarizeWhenMultipleArrive() throws {
        var aggregator = DiscordChannelAggregator(window: 300, maxSummaryCharacters: 1_000)
        let destination = BarkPushDestination(
            baseURL: URL(string: "https://api.day.app")!,
            deviceKey: "abc123",
            iconURL: nil
        )

        let first = try XCTUnwrap(makeParsed(author: "A", body: "第一条"))
        let second = try XCTUnwrap(makeParsed(author: "B", body: "第二条"))
        let third = try XCTUnwrap(makeParsed(author: "C", body: "第三条"))

        let firstResult = aggregator.enqueue(
            first,
            destinations: [destination],
            now: Date(timeIntervalSince1970: 0)
        )
        XCTAssertTrue(firstResult.summaries.isEmpty)

        let secondResult = aggregator.enqueue(
            second,
            destinations: [destination],
            now: Date(timeIntervalSince1970: 60)
        )
        let thirdResult = aggregator.enqueue(
            third,
            destinations: [destination],
            now: Date(timeIntervalSince1970: 120)
        )
        XCTAssertTrue(secondResult.summaries.isEmpty)
        XCTAssertTrue(thirdResult.summaries.isEmpty)

        let summaries = aggregator.flushDue(now: Date(timeIntervalSince1970: 301))
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries.first?.messageCount, 3)
        XCTAssertEqual(summaries.first?.notification.title, "#频道 · 服务器（3条）")
        XCTAssertEqual(summaries.first?.destinations.first?.group, "Discord 频道")
        XCTAssertTrue(summaries.first?.notification.body.contains("A: 第一条") == true)
        XCTAssertTrue(summaries.first?.notification.body.contains("B: 第二条") == true)
        XCTAssertTrue(summaries.first?.notification.body.contains("C: 第三条") == true)
    }

    func testSingleLowFrequencyMessageWaitsForWindowThenSendsOriginalMessage() throws {
        var aggregator = DiscordChannelAggregator(window: 300)
        let destination = BarkPushDestination(
            baseURL: URL(string: "https://api.day.app")!,
            deviceKey: "abc123",
            iconURL: nil
        )

        let first = try XCTUnwrap(makeParsed(author: "A", body: "第一条"))
        let result = aggregator.enqueue(
            first,
            destinations: [destination],
            now: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(result.summaries.isEmpty)

        let summaries = aggregator.flushDue(now: Date(timeIntervalSince1970: 301))
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries.first?.messageCount, 1)
        XCTAssertEqual(summaries.first?.destinations.first?.group, "Discord 频道")
        XCTAssertEqual(summaries.first?.notification.body, "第一条")
    }

    private func makeParsed(author: String, body: String) -> ParsedDiscordNotification? {
        ParsedDiscordNotification.parse(
            ForwardedNotification(
                source: "Discord \(author) (#频道",
                title: "\(author) (#频道, 服务器)",
                body: body,
                identifier: "\(author)-\(body)"
            )
        )
    }
}
