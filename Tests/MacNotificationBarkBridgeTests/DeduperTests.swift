import Foundation
import Testing
@testable import MacNotificationBarkBridge

@Test func deduperSkipsRecentDuplicates() {
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

    #expect(first == [notification])
    #expect(second.isEmpty)
    #expect(third == [notification])
}
