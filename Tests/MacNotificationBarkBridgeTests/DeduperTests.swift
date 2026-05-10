import Foundation
import XCTest
@testable import MacNotificationBarkBridge

final class DeduperTests: XCTestCase {
    func testDeduperSkipsRecentDuplicates() {
        var deduper = Deduper(window: 300)
        let notification = ForwardedNotification(
            source: "Messages",
            title: "Alice",
            body: "Meet at 8",
            identifier: "n1"
        )

        let first = deduper.filterNew([notification], now: Date(timeIntervalSince1970: 100))
        let second = deduper.filterNew([notification], now: Date(timeIntervalSince1970: 200))
        let third = deduper.filterNew([notification], now: Date(timeIntervalSince1970: 450))

        XCTAssertEqual(first, [notification])
        XCTAssertTrue(second.isEmpty)
        XCTAssertEqual(third, [notification])
    }

    func testDeduperSkipsDiscordReparseWithDifferentSourceShape() {
        var deduper = Deduper(window: 300)
        let firstNotification = ForwardedNotification(
            source: "Discord ⁨站长转发1⁩ (⁨#猫姐聊天区⁩",
            title: "⁨站长转发1⁩ (⁨#猫姐聊天区⁩, ⁨猫姐会员频道⁩)",
            body: "**Tracey**: 今天没夜盘吧",
            identifier: "n1"
        )
        let reparsedNotification = ForwardedNotification(
            source: "Discord",
            title: "⁨站长转发1⁩ (⁨#猫姐聊天区⁩, ⁨猫姐会员频道⁩)",
            body: "**Tracey**: 今天没夜盘吧",
            identifier: "n1"
        )

        let first = deduper.filterNew([firstNotification], now: Date(timeIntervalSince1970: 100))
        let second = deduper.filterNew([reparsedNotification], now: Date(timeIntervalSince1970: 120))

        XCTAssertEqual(first, [firstNotification])
        XCTAssertTrue(second.isEmpty)
    }
}
