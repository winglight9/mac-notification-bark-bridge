import Foundation
import XCTest
@testable import MacNotificationBarkBridge

final class BarkClientTests: XCTestCase {
    func testBarkRequestUsesExpectedEndpointAndFormBody() throws {
        let client = BarkClient(sender: { _ in
            fatalError("No network in unit test")
        })
        let destination = BarkPushDestination(
            baseURL: URL(string: "https://api.day.app")!,
            deviceKey: "abc123",
            iconURL: URL(string: "https://example.com/icon.png")
        )

        let notification = ForwardedNotification(
            source: "Messages",
            title: "Alice",
            body: "Meet at 8",
            identifier: "n1"
        )

        let request = client.makeRequest(for: notification, destination: destination)

        XCTAssertEqual(request.url?.absoluteString, "https://api.day.app/abc123")
        XCTAssertEqual(request.httpMethod, "POST")

        let body = String(data: try XCTUnwrap(request.httpBody), encoding: .utf8)
        XCTAssertTrue(body?.contains("title=Alice") == true)
        XCTAssertTrue(body?.contains("body=Meet%20at%208") == true)
        XCTAssertTrue(body?.contains("group=mac-notification-bark-bridge") == true)
        XCTAssertTrue(body?.contains("level=active") == true)
        XCTAssertTrue(body?.contains("isArchive=1") == true)
        XCTAssertTrue(body?.contains("icon=https://example.com/icon.png") == true)
    }
}
