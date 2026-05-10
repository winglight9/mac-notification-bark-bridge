import Foundation

struct BarkPushDestination: Hashable, Sendable {
    let baseURL: URL
    let deviceKey: String
    let iconURL: URL?
    let group: String

    init(
        baseURL: URL,
        deviceKey: String,
        iconURL: URL?,
        group: String = "mac-notification-bark-bridge"
    ) {
        self.baseURL = baseURL
        self.deviceKey = deviceKey
        self.iconURL = iconURL
        self.group = group
    }

    func withGroup(_ group: String) -> BarkPushDestination {
        BarkPushDestination(
            baseURL: baseURL,
            deviceKey: deviceKey,
            iconURL: iconURL,
            group: group
        )
    }
}

struct BarkClient: Sendable {
    typealias Sender = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    let sender: Sender

    init(
        sender: @escaping Sender = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.sender = sender
    }

    func makeRequest(for notification: ForwardedNotification, destination: BarkPushDestination) -> URLRequest {
        let endpoint = destination.baseURL
            .appendingPathComponent(destination.deviceKey, isDirectory: false)

        var fields = [
            URLQueryItem(name: "title", value: notification.barkTitle),
            URLQueryItem(name: "body", value: notification.body),
            URLQueryItem(name: "group", value: destination.group),
            URLQueryItem(name: "level", value: "active"),
            URLQueryItem(name: "isArchive", value: "1"),
        ]
        if let iconURL = destination.iconURL {
            fields.append(URLQueryItem(name: "icon", value: iconURL.absoluteString))
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = fields.percentEncodedData()
        return request
    }

    func send(_ notification: ForwardedNotification, to destination: BarkPushDestination) async throws {
        let request = makeRequest(for: notification, destination: destination)
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
