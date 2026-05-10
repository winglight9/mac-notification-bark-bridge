import Foundation

struct StoredRoutingRule: Codable, Equatable, Sendable, Identifiable {
    var id: String?
    var name: String?
    var deviceKeys: [String]?
    var barkBaseURL: String?
    var applicationNames: [String]?
    var iconURL: String?

    static let defaults = StoredRoutingRule(
        id: "default-rule",
        name: "默认设备",
        deviceKeys: [""],
        barkBaseURL: "https://api.day.app",
        applicationNames: [],
        iconURL: nil
    )

    func normalized(defaultID: String) -> StoredRoutingRule {
        let normalizedKeys = (deviceKeys ?? Self.defaults.deviceKeys ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .stableUniqued()

        let normalizedApps = (applicationNames ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .stableUniqued()

        return StoredRoutingRule(
            id: id?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? defaultID,
            name: name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "转发规则",
            deviceKeys: normalizedKeys,
            barkBaseURL: barkBaseURL?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? Self.defaults.barkBaseURL,
            applicationNames: normalizedApps,
            iconURL: iconURL?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        )
    }

    func validateForPersistence(index: Int) throws {
        let normalized = normalized(defaultID: "rule-\(index + 1)")
        guard let deviceKeys = normalized.deviceKeys, !deviceKeys.isEmpty else {
            throw BridgeError.invalidFieldValue(
                field: normalized.name ?? "规则 \(index + 1)",
                reason: "请至少填写一个 Bark 设备 Key。"
            )
        }

        if let baseURL = normalized.barkBaseURL,
           URL(string: baseURL) == nil {
            throw BridgeError.invalidFieldValue(
                field: normalized.name ?? "规则 \(index + 1)",
                reason: "Bark 服务地址不是有效的 URL。"
            )
        }

        if let iconURL = normalized.iconURL,
           URL(string: iconURL) == nil {
            throw BridgeError.invalidFieldValue(
                field: normalized.name ?? "规则 \(index + 1)",
                reason: "图标 URL 不是有效的 URL。"
            )
        }
    }

    func resolved(index: Int) throws -> NotificationRoutingRule {
        let normalized = normalized(defaultID: "rule-\(index + 1)")
        try validateForPersistence(index: index)

        let barkBaseURL = try requireURL(
            normalized.barkBaseURL ?? "https://api.day.app",
            failure: BridgeError.invalidBarkBaseURL
        )

        let iconURL: URL?
        if let raw = normalized.iconURL {
            iconURL = try requireURL(
                raw,
                failure: { BridgeError.invalidFieldValue(field: normalized.name ?? "规则 \(index + 1)", reason: "图标 URL 无效：\($0)") }
            )
        } else {
            iconURL = nil
        }

        return NotificationRoutingRule(
            id: normalized.id ?? "rule-\(index + 1)",
            name: normalized.name ?? "转发规则 \(index + 1)",
            barkBaseURL: barkBaseURL,
            deviceKeys: normalized.deviceKeys ?? [],
            applicationNames: normalized.applicationNames ?? [],
            iconURL: iconURL
        )
    }

    private func requireURL(
        _ rawValue: String,
        failure: (String) -> BridgeError
    ) throws -> URL {
        guard let url = URL(string: rawValue) else {
            throw failure(rawValue)
        }
        return url
    }
}

struct StoredConfiguration: Codable, Equatable, Sendable {
    var rules: [StoredRoutingRule]?
    var pollInterval: Double?
    var dryRun: Bool?
    var promptForAccessibility: Bool?
    var dedupeWindow: Double?
    var launchAtLogin: Bool?
    var diagnosticsRetentionDays: Int?
    var idleScreenDimmingEnabled: Bool?
    var idleScreenDimmingDelay: Double?
    var idleScreenDimmingOpacity: Double?

    // Legacy fields kept for migration from the original single-rule format.
    var deviceKey: String?
    var barkBaseURL: String?
    var sourceFilter: String?

    static let defaults = StoredConfiguration(
        rules: [.defaults],
        pollInterval: 2,
        dryRun: false,
        promptForAccessibility: true,
        dedupeWindow: 300,
        launchAtLogin: false,
        diagnosticsRetentionDays: 7,
        idleScreenDimmingEnabled: false,
        idleScreenDimmingDelay: 600,
        idleScreenDimmingOpacity: 1.0,
        deviceKey: nil,
        barkBaseURL: nil,
        sourceFilter: nil
    )

    func normalized() -> StoredConfiguration {
        let migratedRules: [StoredRoutingRule]
        if let rules, !rules.isEmpty {
            migratedRules = rules.enumerated().map { index, rule in
                rule.normalized(defaultID: "rule-\(index + 1)")
            }
        } else {
            let migratedApps = sourceFilter?
                .split(separator: ",")
                .map(String.init)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty } ?? []

            migratedRules = [
                StoredRoutingRule(
                    id: "rule-1",
                    name: "默认设备",
                    deviceKeys: [deviceKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""],
                    barkBaseURL: barkBaseURL?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "https://api.day.app",
                    applicationNames: migratedApps,
                    iconURL: nil
                ).normalized(defaultID: "rule-1")
            ]
        }

        return StoredConfiguration(
            rules: migratedRules,
            pollInterval: pollInterval ?? Self.defaults.pollInterval,
            dryRun: dryRun ?? Self.defaults.dryRun,
            promptForAccessibility: promptForAccessibility ?? Self.defaults.promptForAccessibility,
            dedupeWindow: dedupeWindow ?? Self.defaults.dedupeWindow,
            launchAtLogin: launchAtLogin ?? Self.defaults.launchAtLogin,
            diagnosticsRetentionDays: diagnosticsRetentionDays ?? Self.defaults.diagnosticsRetentionDays,
            idleScreenDimmingEnabled: idleScreenDimmingEnabled ?? Self.defaults.idleScreenDimmingEnabled,
            idleScreenDimmingDelay: idleScreenDimmingDelay ?? Self.defaults.idleScreenDimmingDelay,
            idleScreenDimmingOpacity: idleScreenDimmingOpacity ?? Self.defaults.idleScreenDimmingOpacity,
            deviceKey: nil,
            barkBaseURL: nil,
            sourceFilter: nil
        )
    }

    func validateForPersistence() throws {
        let normalized = normalized()

        guard let rules = normalized.rules, !rules.isEmpty else {
            throw BridgeError.invalidFieldValue(
                field: "转发规则",
                reason: "请至少配置一条规则。"
            )
        }

        if let pollInterval = normalized.pollInterval,
           pollInterval <= 0 {
            throw BridgeError.invalidFieldValue(
                field: "轮询间隔",
                reason: "请输入大于 0 的值。"
            )
        }

        if let dedupeWindow = normalized.dedupeWindow,
           dedupeWindow <= 0 {
            throw BridgeError.invalidFieldValue(
                field: "去重窗口",
                reason: "请输入大于 0 的值。"
            )
        }

        if let diagnosticsRetentionDays = normalized.diagnosticsRetentionDays,
           diagnosticsRetentionDays < 7 {
            throw BridgeError.invalidFieldValue(
                field: "诊断保留天数",
                reason: "至少保留 7 天。"
            )
        }

        if let idleScreenDimmingDelay = normalized.idleScreenDimmingDelay,
           idleScreenDimmingDelay <= 0 {
            throw BridgeError.invalidFieldValue(
                field: "空闲遮罩延迟",
                reason: "请输入大于 0 的秒数。"
            )
        }

        if let idleScreenDimmingOpacity = normalized.idleScreenDimmingOpacity,
           !(0...1).contains(idleScreenDimmingOpacity) {
            throw BridgeError.invalidFieldValue(
                field: "空闲遮罩透明度",
                reason: "请输入 0 到 1 之间的数值。"
            )
        }

        try rules.enumerated().forEach { index, rule in
            try rule.validateForPersistence(index: index)
        }
    }

    func resolved() throws -> AppConfiguration {
        let normalized = normalized()
        try normalized.validateForPersistence()

        let interval = normalized.pollInterval ?? 2
        let dedupe = normalized.dedupeWindow ?? 300
        let resolvedRules = try (normalized.rules ?? []).enumerated().map { index, rule in
            try rule.resolved(index: index)
        }

        return AppConfiguration(
            rules: resolvedRules,
            pollInterval: interval,
            dryRun: normalized.dryRun ?? false,
            runOnce: false,
            dumpTree: false,
            fixturePath: nil,
            promptForAccessibility: normalized.promptForAccessibility ?? true,
            dedupeWindow: dedupe,
            launchAtLogin: normalized.launchAtLogin ?? false,
            diagnosticsRetentionDays: normalized.diagnosticsRetentionDays ?? 7,
            idleScreenDimmingEnabled: normalized.idleScreenDimmingEnabled ?? false,
            idleScreenDimmingDelay: normalized.idleScreenDimmingDelay ?? 600,
            idleScreenDimmingOpacity: normalized.idleScreenDimmingOpacity ?? 1.0
        )
    }
}

struct ConfigurationStore {
    let configurationDirectoryProvider: () throws -> URL
    let templateDataProvider: () throws -> Data

    init(
        configurationDirectoryProvider: @escaping () throws -> URL = Self.defaultConfigurationDirectory,
        templateDataProvider: @escaping () throws -> Data = Self.bundledTemplateData
    ) {
        self.configurationDirectoryProvider = configurationDirectoryProvider
        self.templateDataProvider = templateDataProvider
    }

    func configurationDirectoryURL() throws -> URL {
        try configurationDirectoryProvider()
    }

    func configurationURL() throws -> URL {
        try configurationDirectoryURL()
            .appendingPathComponent("config.json", isDirectory: false)
    }

    func configurationExampleURL() throws -> URL {
        try configurationDirectoryURL()
            .appendingPathComponent("config.example.jsonc", isDirectory: false)
    }

    @discardableResult
    func ensureConfigurationFileExists() throws -> URL {
        let directoryURL = try configurationDirectoryURL()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try ensureConfigurationExampleFileExists()

        let fileURL = directoryURL.appendingPathComponent("config.json", isDirectory: false)
        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            return fileURL
        }

        try templateDataProvider().write(to: fileURL, options: .atomic)
        return fileURL
    }

    func load() throws -> AppConfiguration {
        try loadStoredConfiguration().resolved()
    }

    func loadStoredConfiguration() throws -> StoredConfiguration {
        let fileURL = try ensureConfigurationFileExists()

        do {
            let data = try Data(contentsOf: fileURL)
            let normalizedData = try decodeJSONCIfNeeded(from: data)
            return try JSONDecoder().decode(StoredConfiguration.self, from: normalizedData)
        } catch let error as BridgeError {
            throw error
        } catch {
            throw BridgeError.invalidConfigurationFile(
                path: fileURL.path,
                reason: error.localizedDescription
            )
        }
    }

    func save(_ storedConfiguration: StoredConfiguration) throws {
        let normalized = storedConfiguration.normalized()
        try normalized.validateForPersistence()

        let fileURL = try ensureConfigurationFileExists()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(normalized)
        try data.write(to: fileURL, options: .atomic)
    }

    static func defaultConfigurationDirectory() throws -> URL {
        guard let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw BridgeError.invalidConfigurationFile(
                path: "~",
                reason: "Unable to resolve Application Support directory."
            )
        }

        return baseURL.appendingPathComponent("MacNotificationBarkBridge", isDirectory: true)
    }

    static func bundledTemplateData() throws -> Data {
        guard let url = Bundle.module.url(
            forResource: "config.template",
            withExtension: "json",
            subdirectory: "Resources"
        ) else {
            throw BridgeError.missingBundledTemplate
        }
        return try Data(contentsOf: url)
    }

    @discardableResult
    func ensureConfigurationExampleFileExists() throws -> URL {
        let fileURL = try configurationExampleURL()
        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            return fileURL
        }

        try templateDataProvider().write(to: fileURL, options: .atomic)
        return fileURL
    }

    private func decodeJSONCIfNeeded(from data: Data) throws -> Data {
        guard let text = String(data: data, encoding: .utf8) else {
            return data
        }

        let stripped = stripComments(from: text)
        guard let strippedData = stripped.data(using: .utf8) else {
            throw BridgeError.invalidConfigurationFile(
                path: "config.json",
                reason: "无法解析带注释的配置文件。"
            )
        }
        return strippedData
    }

    private func stripComments(from text: String) -> String {
        enum State {
            case normal
            case string
            case lineComment
            case blockComment
        }

        var result = ""
        var state = State.normal
        var iterator = text.makeIterator()
        var previous: Character?
        var pending: Character?

        while true {
            let current: Character?
            if let buffered = pending {
                current = buffered
                pending = nil
            } else {
                current = iterator.next()
            }

            guard let character = current else {
                break
            }

            switch state {
            case .normal:
                if character == "\"" {
                    result.append(character)
                    state = .string
                } else if character == "/" {
                    if let next = iterator.next() {
                        if next == "/" {
                            state = .lineComment
                        } else if next == "*" {
                            state = .blockComment
                        } else {
                            result.append(character)
                            pending = next
                        }
                    } else {
                        result.append(character)
                    }
                } else {
                    result.append(character)
                }

            case .string:
                result.append(character)
                if character == "\"" && previous != "\\" {
                    state = .normal
                }

            case .lineComment:
                if character == "\n" {
                    result.append(character)
                    state = .normal
                }

            case .blockComment:
                if previous == "*" && character == "/" {
                    state = .normal
                } else if character == "\n" {
                    result.append(character)
                }
            }

            previous = character
        }

        return result
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
