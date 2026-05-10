import Foundation

struct BridgeService: Sendable {
    private struct ScanSummary: Equatable, Sendable {
        let panelVisible: Bool
        let topLevelChildren: Int
        let totalNodes: Int
        let matches: Int
        let fresh: Int
    }

    let configuration: AppConfiguration
    let snapshotProvider: any NotificationSnapshotProviding
    let parser: NotificationParser
    let barkClient: BarkClient
    let logger: any BridgeLogging
    var deduper: Deduper
    var discordAggregator: DiscordChannelAggregator
    private var lastScanSummary: ScanSummary?

    init(
        configuration: AppConfiguration,
        snapshotProvider: any NotificationSnapshotProviding,
        parser: NotificationParser = NotificationParser(),
        barkClient: BarkClient,
        logger: any BridgeLogging = NoopBridgeLogger()
    ) {
        self.configuration = configuration
        self.snapshotProvider = snapshotProvider
        self.parser = parser
        self.barkClient = barkClient
        self.logger = logger
        self.deduper = Deduper(window: configuration.dedupeWindow)
        self.discordAggregator = DiscordChannelAggregator()
        self.lastScanSummary = nil
    }

    mutating func run(log: (String) -> Void = { print($0) }) async throws {
        repeat {
            let notifications = try await runOnce()

            for notification in notifications {
                log(logMessage(for: notification))
            }

            if configuration.runOnce {
                break
            }

            let nanoseconds = UInt64(configuration.pollInterval * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanoseconds)
        } while true
    }

    mutating func runOnce() async throws -> [ForwardedNotification] {
        let tree: AccessibilityNode
        do {
            tree = try await snapshotProvider.snapshot()
        } catch {
            await logger.log(.error, "scan.snapshot_failed error=\(describe(error))")
            throw error
        }

        await logger.storeSnapshot(tree)

        if configuration.dumpTree {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(tree)
            if let json = String(data: data, encoding: .utf8) {
                print(json)
            }
        }

        let notifications = parser.parse(from: tree, sourceFilter: nil)
        let fresh = deduper.filterNew(notifications)
        let summary = ScanSummary(
            panelVisible: tree.notificationPanelVisible,
            topLevelChildren: tree.children.count,
            totalNodes: tree.totalNodeCount,
            matches: notifications.count,
            fresh: fresh.count
        )
        if summary != lastScanSummary {
            await logger.log(
                .info,
                "scan.snapshot rootRole=\(tree.role ?? "-") rootTitle=\(tree.title ?? "-") topLevelChildren=\(tree.children.count) totalNodes=\(tree.totalNodeCount)"
            )
            await logger.log(
                .info,
                "scan.parsed matches=\(notifications.count) fresh=\(fresh.count) deduped=\(notifications.count - fresh.count)"
            )
            if summary.panelVisible && notifications.isEmpty {
                await logger.log(.warning, "scan.zero_matches latestSnapshotUpdated=true")
            }
            lastScanSummary = summary
        }

        for notification in fresh {
            let destinations = deliveryDestinations(for: notification)
            await logger.log(.info, notificationLogMessage(for: notification, destinations: destinations))
            guard !destinations.isEmpty else {
                await logger.log(.info, "scan.skipped no_matching_rule source=\(notification.source)")
                continue
            }

            if let parsedDiscord = ParsedDiscordNotification.parse(notification) {
                let result = discordAggregator.enqueue(
                    parsedDiscord,
                    destinations: destinations,
                    now: Date()
                )
                for summary in result.summaries {
                    await send(summary.notification, to: summary.destinations)
                    await logger.log(
                        .info,
                        "discord.summary_forwarded channel=\(escapedLogValue(summary.channel)) messages=\(summary.messageCount)"
                    )
                }
                continue
            }

            guard !configuration.dryRun else {
                continue
            }
            await send(notification, to: destinations)
        }

        let dueSummaries = discordAggregator.flushDue(now: Date())
        for summary in dueSummaries {
            await send(summary.notification, to: summary.destinations)
            await logger.log(
                .info,
                "discord.summary_forwarded channel=\(escapedLogValue(summary.channel)) messages=\(summary.messageCount)"
            )
        }

        return fresh
    }

    func notificationLogMessage(for notification: ForwardedNotification, destinations: [BarkPushDestination]) -> String {
        "scan.notification source=\(escapedLogValue(notification.source)) title=\(escapedLogValue(notification.title)) body=\(escapedLogValue(notification.body)) identifier=\(escapedLogValue(notification.identifier ?? "-")) deliveries=\(destinations.count)"
    }

    private func escapedLogValue(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    func logMessage(for notification: ForwardedNotification) -> String {
        if configuration.dryRun {
            return "Would send Bark: [\(notification.barkTitle)] \(notification.body)"
        }
        return "Forwarded: [\(notification.barkTitle)] \(notification.body)"
    }

    private func send(_ notification: ForwardedNotification, to destinations: [BarkPushDestination]) async {
        guard !configuration.dryRun else {
            return
        }

        for destination in destinations {
            do {
                try await barkClient.send(notification, to: destination)
                await logger.log(
                    .info,
                    "scan.forwarded title=\(notification.barkTitle) deviceKeySuffix=\(destination.deviceKey.suffix(6))"
                )
            } catch {
                await logger.log(
                    .error,
                    "scan.forward_failed title=\(notification.barkTitle) deviceKeySuffix=\(destination.deviceKey.suffix(6)) error=\(describe(error))"
                )
            }
        }
    }

    private func deliveryDestinations(for notification: ForwardedNotification) -> [BarkPushDestination] {
        var seen = Set<String>()
        var destinations: [BarkPushDestination] = []

        for rule in configuration.rules where rule.matches(notification) {
            for deviceKey in rule.deviceKeys {
                let destination = BarkPushDestination(
                    baseURL: rule.barkBaseURL,
                    deviceKey: deviceKey,
                    iconURL: rule.iconURL
                )
                let key = "\(destination.baseURL.absoluteString)|\(destination.deviceKey)"
                guard seen.insert(key).inserted else {
                    continue
                }
                destinations.append(destination)
            }
        }

        return destinations
    }
}

struct Deduper: Sendable {
    let window: TimeInterval
    private var seen: [String: Date] = [:]
    private var seenDiscordBodyKeys: [String: Date] = [:]

    init(window: TimeInterval) {
        self.window = window
    }

    mutating func filterNew(_ notifications: [ForwardedNotification], now: Date = Date()) -> [ForwardedNotification] {
        seen = seen.filter { now.timeIntervalSince($0.value) < window }
        seenDiscordBodyKeys = seenDiscordBodyKeys.filter { now.timeIntervalSince($0.value) < window }

        return notifications.filter { notification in
            if let discordKey = discordBodyKey(for: notification) {
                if seenDiscordBodyKeys[discordKey] != nil {
                    return false
                }
                seenDiscordBodyKeys[discordKey] = now
            }

            if seen[notification.signature] != nil {
                return false
            }
            seen[notification.signature] = now
            return true
        }
    }

    private func discordBodyKey(for notification: ForwardedNotification) -> String? {
        guard let parsed = ParsedDiscordNotification.parse(notification) else {
            return nil
        }

        let normalizedBody = notification.body
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .prefix(120)

        let serverKey = parsed.server?.fingerprint ?? "-"
        return [
            parsed.channel.fingerprint,
            serverKey,
            String(normalizedBody).fingerprint,
        ].joined(separator: "|")
    }
}

func makeBridgeService(
    configuration: AppConfiguration,
    logger: (any BridgeLogging)? = nil
) -> BridgeService {
    let logger = logger ?? FileBridgeLogger(retentionDays: configuration.diagnosticsRetentionDays)
    let snapshotProvider: any NotificationSnapshotProviding
    if let fixturePath = configuration.fixturePath {
        snapshotProvider = FixtureSnapshotProvider(path: fixturePath)
    } else {
        snapshotProvider = AccessibilityNotificationSnapshotProvider(
            promptForAccessibility: configuration.promptForAccessibility,
            logger: logger
        )
    }

    let barkClient = BarkClient()

    return BridgeService(
        configuration: configuration,
        snapshotProvider: snapshotProvider,
        barkClient: barkClient,
        logger: logger
    )
}
