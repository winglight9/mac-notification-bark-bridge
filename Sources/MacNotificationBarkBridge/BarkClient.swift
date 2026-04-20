import Foundation

struct BarkClient: Sendable {
    typealias Sender = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    let baseURL: URL
    let deviceKey: String
    let sender: Sender

    init(
        baseURL: URL,
        deviceKey: String,
        sender: @escaping Sender = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.baseURL = baseURL
        self.deviceKey = deviceKey
        self.sender = sender
    }

    func makeRequest(for notification: ForwardedNotification) -> URLRequest {
        let endpoint = baseURL
            .appendingPathComponent(deviceKey, isDirectory: false)

        let fields = [
            URLQueryItem(name: "title", value: notification.barkTitle),
            URLQueryItem(name: "body", value: notification.body),
            URLQueryItem(name: "group", value: "mac-notification-bark-bridge"),
            URLQueryItem(name: "level", value: "active"),
            URLQueryItem(name: "isArchive", value: "1"),
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = fields.percentEncodedData()
        return request
    }

    func send(_ notification: ForwardedNotification) async throws {
        let request = makeRequest(for: notification)
        let (data, response) = try await sender(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            return
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw BridgeError.barkRejected(statusCode: httpResponse.statusCode, body: body)
        }
    }
}

private extension Array where Element == URLQueryItem {
    func percentEncodedData() -> Data? {
        var components = URLComponents()
        components.queryItems = self
        return components.percentEncodedQuery?.data(using: .utf8)
    }
}
