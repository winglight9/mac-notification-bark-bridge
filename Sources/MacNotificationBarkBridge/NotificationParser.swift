import Foundation

struct NotificationParser: Sendable {
    private let containerRoles: Set<String> = [
        "AXApplication",
        "AXGroup",
        "AXList",
        "AXRow",
        "AXScrollArea",
        "AXWindow",
    ]
    private let notificationSubroles: Set<String> = [
        "AXNotificationCenterBanner",
        "AXNotificationCenterBannerStack",
    ]

    private let ignoredExactTexts: Set<String> = [
        "Notification Center",
        "通知中心",
        "通知",
        "Close",
        "关闭",
        "Options",
        "选项",
        "Clear",
        "Clear All",
        "清除",
        "清除全部",
        "Earlier Today",
        "今天稍早",
        "No Older Notifications",
        "没有更早的通知",
        "Now",
        "刚刚",
    ]

    func parse(from root: AccessibilityNode, sourceFilter: String?) -> [ForwardedNotification] {
        let filter = sourceFilter?.fingerprint
        let matches = collectCandidates(from: root, filter: filter)

        var exactSeen = Set<String>()
        let exactUnique = matches.filter { exactSeen.insert($0.signature).inserted }
        let strongerTitleBodySignatures = Set(
            exactUnique
                .filter { !$0.usesFallbackSource }
                .map(\.titleBodySignature)
        )

        return exactUnique.filter { notification in
            guard notification.usesFallbackSource else {
                return true
            }

            return !strongerTitleBodySignatures.contains(notification.titleBodySignature)
        }
    }

    private func collectCandidates(
        from node: AccessibilityNode,
        filter: String?
    ) -> [ForwardedNotification] {
        let childMatches = node.children.flatMap { child in
            collectCandidates(from: child, filter: filter)
        }

        if let notification = candidate(from: node), matchesFilter(notification, filter: filter) {
            let childContentSignatures = Set(childMatches.map(\.contentSignature))
            if !childContentSignatures.contains(notification.contentSignature) {
                return childMatches + [notification]
            }
        }

        return childMatches
    }

    private func candidate(from node: AccessibilityNode) -> ForwardedNotification? {
        guard let role = node.role, containerRoles.contains(role) else {
            return nil
        }

        let texts = leafTexts(in: node)
            .map(cleanText)
            .filter { !$0.isEmpty }
            .filter { !ignoredExactTexts.contains($0) }
            .filter { !looksLikeRelativeTime($0) }
            .stableUniqued()

        if let subrole = node.subrole, notificationSubroles.contains(subrole) {
            return notificationCenterCandidate(from: node, texts: texts)
        }

        guard texts.count >= 2, texts.count <= 6 else {
            return nil
        }

        let joined = texts.joined(separator: " ")
        guard joined.count <= 400 else {
            return nil
        }

        let source = texts[0]
        let title: String
        let body: String

        if texts.count == 2 {
            title = source
            body = texts[1]
        } else {
            title = texts[1]
            body = texts.dropFirst(2).joined(separator: "\n")
        }

        guard !body.isEmpty else {
            return nil
        }

        return ForwardedNotification(
            source: source,
            title: title,
            body: body,
            identifier: node.identifier
        )
    }

    private func notificationCenterCandidate(
        from node: AccessibilityNode,
        texts: [String]
    ) -> ForwardedNotification? {
        guard texts.count >= 2 else {
            return nil
        }

        let title = texts[0]
        let body = texts.dropFirst().joined(separator: "\n")
        guard !body.isEmpty else {
            return nil
        }

        let source = notificationSource(from: node, title: title) ?? title

        return ForwardedNotification(
            source: source,
            title: title,
            body: body,
            identifier: node.identifier
        )
    }

    private func notificationSource(from node: AccessibilityNode, title: String) -> String? {
        guard let description = node.nodeDescription.map(cleanText), !description.isEmpty else {
            return nil
        }

        let separators = ["，", ","]
        guard let separator = separators.first(where: { description.contains($0) }) else {
            return nil
        }

        let prefix = description
            .components(separatedBy: separator)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !prefix.isEmpty else {
            return nil
        }

        if prefix.hasSuffix(title) {
            let stripped = String(prefix.dropLast(title.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !stripped.isEmpty {
                return stripped
            }
        }

        return prefix
    }

    private func leafTexts(in node: AccessibilityNode) -> [String] {
        if node.children.isEmpty {
            return [node.title, node.value, node.nodeDescription].compactMap { $0 }
        }

        return node.children.flatMap { leafTexts(in: $0) }
    }

    private func cleanText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func matchesFilter(_ notification: ForwardedNotification, filter: String?) -> Bool {
        guard let filter, !filter.isEmpty else {
            return true
        }

        let haystack = [
            notification.source,
            notification.title,
            notification.body,
        ].joined(separator: "\n").fingerprint

        return haystack.contains(filter)
    }

    private func looksLikeRelativeTime(_ text: String) -> Bool {
        let value = text.fingerprint

        let patterns = [
            #"^\d{1,2}:\d{2}$"#,
            #"^\d+\s?(m|min|mins|minute|minutes|h|hr|hrs|hour|hours|s|sec|secs|second|seconds)\s?(ago)?$"#,
            #"^(刚刚|\d+分钟前|\d+小时前)$"#,
        ]

        return patterns.contains { pattern in
            value.range(of: pattern, options: .regularExpression) != nil
        }
    }
}
