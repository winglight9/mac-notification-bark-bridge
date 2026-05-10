import Foundation

struct ParsedDiscordNotification: Equatable, Sendable {
    let author: String
    let channel: String
    let server: String?
    let message: String
    let original: ForwardedNotification

    static func parse(_ notification: ForwardedNotification) -> ParsedDiscordNotification? {
        let source = clean(notification.source)
        let title = clean(notification.title)
        guard source.fingerprint.hasPrefix("discord") || title.fingerprint == "discord" || title.contains("#") else {
            return nil
        }

        guard let header = parseHeader(title) ?? parseHeader(source.removingDiscordPrefix()) else {
            return nil
        }

        let message = clean(notification.body)

        return ParsedDiscordNotification(
            author: resolvedAuthor(
                headerAuthor: header.author,
                source: source,
                message: message
            ),
            channel: header.channel,
            server: header.server,
            message: message,
            original: notification
        )
    }

    private static func parseHeader(_ value: String) -> (author: String, channel: String, server: String?)? {
        let closeBoundary = value.lastIndex(of: ")") ?? value.endIndex

        for openIndex in value.indices.reversed() where value[openIndex] == "(" && openIndex < closeBoundary {
            let author = value[..<openIndex]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty ?? "未知发言人"
            let context = value[value.index(after: openIndex)..<closeBoundary]
                .split(separator: ",", maxSplits: 1)
                .map(String.init)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

            guard let channel = context.first?.nilIfEmpty, channel.contains("#") else {
                continue
            }

            let server = context.dropFirst().first?.nilIfEmpty
            return (author, channel, server)
        }

        return nil
    }

    private static func clean(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{2066}", with: "")
            .replacingOccurrences(of: "\u{2067}", with: "")
            .replacingOccurrences(of: "\u{2068}", with: "")
            .replacingOccurrences(of: "\u{2069}", with: "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func resolvedAuthor(
        headerAuthor: String,
        source: String,
        message: String
    ) -> String {
        guard isRelayAuthor(headerAuthor) else {
            return headerAuthor
        }

        return extractForwardedAuthor(from: message)
            ?? extractForwardedAuthor(from: source)
            ?? headerAuthor
    }

    private static func isRelayAuthor(_ author: String) -> Bool {
        author.fingerprint.hasPrefix("站长转发")
    }

    private static func extractForwardedAuthor(from value: String) -> String? {
        let pattern = #"\*\*([^*]+)\*\*[:：]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let nsRange = NSRange(value.startIndex..<value.endIndex, in: value)
        let matches = regex.matches(in: value, range: nsRange)

        for match in matches.reversed() {
            guard match.numberOfRanges >= 2,
                  let range = Range(match.range(at: 1), in: value) else {
                continue
            }

            let author = clean(String(value[range]))
            if !author.isEmpty {
                return author
            }
        }

        return nil
    }
}

struct DiscordChannelSummary: Equatable, Sendable {
    let channel: String
    let messageCount: Int
    let notification: ForwardedNotification
    let destinations: [BarkPushDestination]
}

struct DiscordEnqueueResult: Equatable, Sendable {
    let summaries: [DiscordChannelSummary]
}

struct DiscordChannelAggregator: Sendable {
    private struct PendingMessage: Equatable, Sendable {
        let receivedAt: Date
        let parsed: ParsedDiscordNotification
    }

    private struct Bucket: Equatable, Sendable {
        let startedAt: Date
        let channel: String
        let server: String?
        var messages: [PendingMessage]
        var destinations: [BarkPushDestination]
    }

    let window: TimeInterval
    let maxSummaryCharacters: Int
    private var buckets: [String: Bucket] = [:]

    init(window: TimeInterval = 300, maxSummaryCharacters: Int = 3_500) {
        self.window = window
        self.maxSummaryCharacters = maxSummaryCharacters
    }

    mutating func enqueue(
        _ parsed: ParsedDiscordNotification,
        destinations: [BarkPushDestination],
        now: Date
    ) -> DiscordEnqueueResult {
        var summaries: [DiscordChannelSummary] = []
        let key = bucketKey(for: parsed)

        if let bucket = buckets[key], now.timeIntervalSince(bucket.startedAt) >= window {
            if let summary = makeSummary(from: bucket) {
                summaries.append(summary)
            }
            buckets.removeValue(forKey: key)
        }

        let pending = PendingMessage(receivedAt: now, parsed: parsed)
        if var bucket = buckets[key] {
            bucket.messages.append(pending)
            bucket.destinations = mergedDestinations(bucket.destinations, destinations)
            buckets[key] = bucket
            return DiscordEnqueueResult(summaries: summaries)
        } else {
            buckets[key] = Bucket(
                startedAt: now,
                channel: parsed.channel,
                server: parsed.server,
                messages: [pending],
                destinations: destinations
            )
            return DiscordEnqueueResult(summaries: summaries)
        }
    }

    mutating func flushDue(now: Date) -> [DiscordChannelSummary] {
        let dueKeys = buckets
            .filter { now.timeIntervalSince($0.value.startedAt) >= window }
            .map(\.key)

        return dueKeys.compactMap { key in
            guard let bucket = buckets.removeValue(forKey: key) else {
                return nil
            }
            return makeSummary(from: bucket)
        }
    }

    private func makeSummary(from bucket: Bucket) -> DiscordChannelSummary? {
        guard !bucket.messages.isEmpty else {
            return nil
        }

        if bucket.messages.count == 1, let onlyMessage = bucket.messages.first {
            return DiscordChannelSummary(
                channel: bucket.channel,
                messageCount: 1,
                notification: onlyMessage.parsed.original,
                destinations: discordDestinations(for: bucket)
            )
        }

        let title = summaryTitle(for: bucket)
        let body = truncatedBody(for: bucket.messages)
        let notification = ForwardedNotification(
            source: "Discord",
            title: title,
            body: body,
            identifier: "discord-summary-\(bucketFingerprint(for: bucket))-\(Int(bucket.startedAt.timeIntervalSince1970))"
        )

        return DiscordChannelSummary(
            channel: bucket.channel,
            messageCount: bucket.messages.count,
            notification: notification,
            destinations: discordDestinations(for: bucket)
        )
    }

    private func summaryTitle(for bucket: Bucket) -> String {
        if let server = bucket.server?.nilIfEmpty {
            return "\(bucket.channel) · \(server)（\(bucket.messages.count)条）"
        }
        return "\(bucket.channel)（\(bucket.messages.count)条）"
    }

    private func bucketKey(for parsed: ParsedDiscordNotification) -> String {
        let serverKey = parsed.server?.fingerprint ?? "-"
        return "\(parsed.channel.fingerprint)|\(serverKey)"
    }

    private func bucketFingerprint(for bucket: Bucket) -> String {
        let serverKey = bucket.server?.fingerprint ?? "-"
        return "\(bucket.channel.fingerprint)|\(serverKey)"
    }

    private func discordDestinations(for bucket: Bucket) -> [BarkPushDestination] {
        let group = barkGroupName(for: bucket.channel)
        return bucket.destinations.map { $0.withGroup(group) }
    }

    private func barkGroupName(for channel: String) -> String {
        var output = ""
        var previousWasSeparator = false

        for scalar in channel.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" {
                output.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if !output.isEmpty && !previousWasSeparator {
                output.append(" ")
                previousWasSeparator = true
            }
        }

        let channelName = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "频道"

        return "Discord \(String(channelName.prefix(64)))"
    }

    private func truncatedBody(for messages: [PendingMessage]) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = DiagnosticsStore.diagnosticsTimeZone
        formatter.dateFormat = "HH:mm:ss"

        let body = messages
            .map { message in
                let time = formatter.string(from: message.receivedAt)
                return "\(time) \(message.parsed.author): \(message.parsed.message)"
            }
            .joined(separator: "\n")

        guard body.count > maxSummaryCharacters else {
            return body
        }

        let endIndex = body.index(body.startIndex, offsetBy: maxSummaryCharacters)
        return "\(body[..<endIndex])\n...已截断，完整内容见本地日志。"
    }

    private func mergedDestinations(
        _ existing: [BarkPushDestination],
        _ incoming: [BarkPushDestination]
    ) -> [BarkPushDestination] {
        var seen = Set<String>()
        var output: [BarkPushDestination] = []

        for destination in existing + incoming {
            let key = "\(destination.baseURL.absoluteString)|\(destination.deviceKey)|\(destination.iconURL?.absoluteString ?? "-")"
            guard seen.insert(key).inserted else {
                continue
            }
            output.append(destination)
        }

        return output
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    func removingDiscordPrefix() -> String {
        let prefix = "Discord"
        guard hasPrefix(prefix) else {
            return self
        }

        return String(dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
