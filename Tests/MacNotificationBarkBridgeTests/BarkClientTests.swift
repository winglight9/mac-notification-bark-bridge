import Foundation
import Testing
@testable import MacNotificationBarkBridge

@Test func barkRequestUsesExpectedEndpointAndFormBody() throws {
    let client = BarkClient(
        baseURL: URL(string: "https://api.day.app")!,
        deviceKey: "abc123",
        sender: { _ in
            fatalError("No network in unit test")
        }
    )

    let notification = ForwardedNotification(
        source: "Messages",
        title: "Alice",
        body: "Meet at 8",
        identifier: "n1"
    )

    let request = client.makeRequest(for: notification)

    #expect(request.url?.absoluteString == "https://api.day.app/abc123")
    #expect(request.httpMethod == "POST")

    let body = String(data: try #require(request.httpBody), encoding: .utf8)
    #expect(body?.contains("title=Messages%20%7C%20Alice") == true)
    #expect(body?.contains("body=Meet%20at%208") == true)
    #expect(body?.contains("group=mac-notification-bark-bridge") == true)
}
