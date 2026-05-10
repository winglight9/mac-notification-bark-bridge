import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ConfigurationWindowController: NSWindowController, NSWindowDelegate {
    private let configurationStore: ConfigurationStore
    private let appCatalog: AppCatalog
    private let onSave: () -> Void
    private let onClose: () -> Void

    private let pollIntervalField = NSTextField(string: "")
    private let dedupeWindowField = NSTextField(string: "")
    private let idleScreenDimmingDelayField = NSTextField(string: "")
    private let dryRunButton = NSButton(checkboxWithTitle: "仅调试，不发送 Bark", target: nil, action: nil)
    private let promptAccessibilityButton = NSButton(
        checkboxWithTitle: "需要时请求辅助功能权限",
        target: nil,
        action: nil
    )
    private let launchAtLoginButton = NSButton(
        checkboxWithTitle: "登录 macOS 时自动启动",
        target: nil,
        action: nil
    )
    private let idleScreenDimmingButton = NSButton(
        checkboxWithTitle: "空闲时显示黑色遮罩，避免真正熄屏",
        target: nil,
        action: nil
    )
    private let statusLabel = NSTextField(wrappingLabelWithString: "")

    init(
        configurationStore: ConfigurationStore,
        appCatalog: AppCatalog = AppCatalog(),
        onSave: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.configurationStore = configurationStore
        self.appCatalog = appCatalog
        self.onSave = onSave
        self.onClose = onClose

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mac 通知 Bark 转发"
        window.center()

        super.init(window: window)

        window.delegate = self
        window.contentView = buildContentView()
        loadFromDisk()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        loadFromDisk()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    private func buildContentView() -> NSView {
        pollIntervalField.placeholderString = "2"
        dedupeWindowField.placeholderString = "300"
        idleScreenDimmingDelayField.placeholderString = "8"

        let introLabel = NSTextField(wrappingLabelWithString:
            "这里只放日常会改的东西。高级规则不在这里手填，需要修改时直接打开配置文件。"
        )
        introLabel.textColor = .secondaryLabelColor

        let explanationLabel = NSTextField(wrappingLabelWithString:
            "当前常用值：轮询 2 秒，去重 300 秒，空闲遮罩 8 分钟。"
        )
        explanationLabel.textColor = .tertiaryLabelColor

        let timingCard = settingsCard(
            title: "扫描与去重",
            subtitle: "控制多久扫描一次，以及同一条消息多久内不重复发。",
            content: verticalFormRows([
                fieldRow(title: "轮询间隔", field: pollIntervalField, unit: "秒"),
                fieldRow(title: "去重窗口", field: dedupeWindowField, unit: "秒"),
            ])
        )

        let dimmingCard = settingsCard(
            title: "息屏保活",
            subtitle: "避免电脑真正熄屏，保持通知采集持续工作。",
            content: verticalGroup([
                idleScreenDimmingButton,
                fieldRow(title: "启动延迟", field: idleScreenDimmingDelayField, unit: "分钟"),
            ])
        )

        let systemCard = settingsCard(
            title: "系统与调试",
            subtitle: "启动方式、权限提示和调试开关都放在这里。",
            content: verticalGroup([
                launchAtLoginButton,
                promptAccessibilityButton,
                dryRunButton,
            ])
        )

        let rulesSummaryLabel = NSTextField(wrappingLabelWithString: rulesSummaryText())
        rulesSummaryLabel.textColor = .secondaryLabelColor

        let reloadButton = NSButton(title: "从磁盘重载", target: self, action: #selector(reloadFromDiskAction(_:)))
        let revealButton = NSButton(title: "打开配置文件", target: self, action: #selector(openConfigurationFile(_:)))
        let rulesButtons = NSStackView(views: [revealButton, reloadButton])
        rulesButtons.orientation = .horizontal
        rulesButtons.spacing = 10

        let rulesCard = settingsCard(
            title: "规则与文件",
            subtitle: "这里只看摘要；新增、删除和高级修改统一走配置文件。",
            content: verticalGroup([
                rulesSummaryLabel,
                rulesButtons,
            ])
        )

        let cardsGrid = NSGridView(views: [
            [timingCard, dimmingCard],
            [systemCard, rulesCard],
        ])
        cardsGrid.rowSpacing = 16
        cardsGrid.columnSpacing = 16
        cardsGrid.xPlacement = .fill
        cardsGrid.yPlacement = .fill
        cardsGrid.row(at: 0).height = 180
        cardsGrid.row(at: 1).height = 180
        cardsGrid.column(at: 0).width = 340
        cardsGrid.column(at: 1).width = 340

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 3

        let saveButton = NSButton(title: "保存", target: self, action: #selector(saveConfiguration(_:)))
        saveButton.keyEquivalent = "\r"
        let buttonRow = NSStackView(views: [saveButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.alignment = .centerY

        let contentStack = NSStackView(views: [
            introLabel,
            explanationLabel,
            cardsGrid,
            statusLabel,
            buttonRow,
        ])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 16

        let contentView = NSView()
        contentView.addSubview(contentStack)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
        ])

        return contentView
    }

    private func settingsCard(title: String, subtitle: String, content: NSView) -> NSView {
        let box = NSBox()
        box.titlePosition = .noTitle
        box.boxType = .custom
        box.borderWidth = 1
        box.cornerRadius = 12
        box.borderColor = .separatorColor
        box.contentViewMargins = NSSize(width: 16, height: 16)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: 13)

        let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 2

        let stack = NSStackView(views: [titleLabel, subtitleLabel, content])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10

        box.contentView = stack
        return box
    }

    private func fieldRow(title: String, field: NSTextField, unit: String) -> NSView {
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 72).isActive = true

        let titleLabel = NSTextField(labelWithString: title)
        let unitLabel = NSTextField(labelWithString: unit)
        unitLabel.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [titleLabel, field, unitLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    private func verticalGroup(_ views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        return stack
    }

    private func verticalFormRows(_ views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        return stack
    }

    private func rulesSummaryText() -> String {
        do {
            let stored = try configurationStore.loadStoredConfiguration().normalized()
            let rules = stored.rules ?? []
            if rules.isEmpty {
                return "当前没有规则。"
            }

            return rules.map { rule in
                let name = normalizedRuleName(rule.name)
                let apps = rule.applicationNames?.isEmpty == false
                    ? rule.applicationNames!.joined(separator: "、")
                    : "全部应用"
                return "• \(name)：\(apps)"
            }.joined(separator: "\n")
        } catch {
            return "规则摘要读取失败，请直接打开配置文件查看。"
        }
    }

    private func normalizedRuleName(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "未命名规则" : trimmed
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.alignment = .right
        field.textColor = .labelColor
        return field
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .boldSystemFont(ofSize: 13)
        field.textColor = .labelColor
        return field
    }

    private func loadFromDisk() {
        do {
            let stored = try configurationStore.loadStoredConfiguration()
            populateFields(with: stored.normalized())

            let configURL = try configurationStore.configurationURL()
            showStatus(
                "正在编辑 \(NSString(string: configURL.path).abbreviatingWithTildeInPath)",
                color: .secondaryLabelColor
            )
        } catch {
            populateFields(with: .defaults)
            showStatus(
                "无法读取当前配置，表单已填入默认值。保存后可修复配置文件。",
                color: .systemOrange
            )
        }
    }

    func populateFields(with stored: StoredConfiguration) {
        let normalized = stored.normalized()
        pollIntervalField.stringValue = formatNumber(normalized.pollInterval ?? 2)
        dedupeWindowField.stringValue = formatNumber(normalized.dedupeWindow ?? 300)
        idleScreenDimmingDelayField.stringValue = formatNumber((normalized.idleScreenDimmingDelay ?? 600) / 60)
        dryRunButton.state = normalized.dryRun == true ? .on : .off
        promptAccessibilityButton.state = normalized.promptForAccessibility == false ? .off : .on
        launchAtLoginButton.state = normalized.launchAtLogin == true ? .on : .off
        idleScreenDimmingButton.state = normalized.idleScreenDimmingEnabled == true ? .on : .off
        _ = normalized.rules ?? [.defaults]
    }

    private func formatNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(value)
    }

    func currentFormConfiguration() throws -> StoredConfiguration {
        let rules = try configurationStore.loadStoredConfiguration().normalized().rules ?? [.defaults]

        return StoredConfiguration(
            rules: rules,
            pollInterval: try parseNumber(
                from: pollIntervalField.stringValue,
                fieldName: "轮询间隔",
                defaultValue: StoredConfiguration.defaults.pollInterval ?? 2
            ),
            dryRun: dryRunButton.state == .on,
            promptForAccessibility: promptAccessibilityButton.state == .on,
            dedupeWindow: try parseNumber(
                from: dedupeWindowField.stringValue,
                fieldName: "去重窗口",
                defaultValue: StoredConfiguration.defaults.dedupeWindow ?? 300
            ),
            launchAtLogin: launchAtLoginButton.state == .on,
            idleScreenDimmingEnabled: idleScreenDimmingButton.state == .on,
            idleScreenDimmingDelay: try parseNumber(
                from: idleScreenDimmingDelayField.stringValue,
                fieldName: "空闲遮罩",
                defaultValue: (StoredConfiguration.defaults.idleScreenDimmingDelay ?? 600) / 60
            ) * 60,
            idleScreenDimmingOpacity: StoredConfiguration.defaults.idleScreenDimmingOpacity,
            deviceKey: nil,
            barkBaseURL: nil,
            sourceFilter: nil
        )
    }

    private func parseNumber(from string: String, fieldName: String, defaultValue: Double) throws -> Double {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return defaultValue
        }

        guard let number = Double(trimmed) else {
            throw BridgeError.invalidFieldValue(
                field: fieldName,
                reason: "请输入数字。"
            )
        }

        return number
    }

    private func showStatus(_ text: String, color: NSColor) {
        statusLabel.stringValue = text
        statusLabel.textColor = color
    }

    var statusTextForTesting: String {
        statusLabel.stringValue
    }

    func saveCurrentForm() throws {
        let stored = try currentFormConfiguration().normalized()
        try configurationStore.save(stored)
        try updateLaunchAtLoginPreference(stored.launchAtLogin ?? false)
        onSave()
        showStatus("已保存，监听状态已重新加载。", color: .systemGreen)
    }

    private func updateLaunchAtLoginPreference(_ enabled: Bool) throws {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }

        guard LaunchAtLoginController.isAvailable else {
            if enabled {
                throw BridgeError.launchAtLoginUnavailable
            }
            return
        }

        if LaunchAtLoginController.isEnabled != enabled {
            try LaunchAtLoginController.setEnabled(enabled)
        }
    }

    @objc private func saveConfiguration(_ sender: Any?) {
        do {
            try saveCurrentForm()
        } catch {
            let message: String
            if let bridgeError = error as? BridgeError {
                message = bridgeError.description
            } else {
                message = error.localizedDescription
            }
            showStatus(message, color: .systemRed)
        }
    }

    @objc private func reloadFromDiskAction(_ sender: Any?) {
        loadFromDisk()
    }

    @objc private func openConfigurationFile(_ sender: Any?) {
        do {
            let url = try configurationStore.configurationURL()
            NSWorkspace.shared.open(url)
        } catch {
            showStatus(error.localizedDescription, color: .systemRed)
        }
    }
}

@MainActor
private final class AppSelectionWindowController: NSWindowController {
    private let allItems: [AppCatalogItem]
    private let onSave: ([String]) -> Void
    private let searchField = NSSearchField()
    private let listStackView = NSStackView()
    private var selectedNames: Set<String>

    init(items: [AppCatalogItem], selectedNames: [String], onSave: @escaping ([String]) -> Void) {
        self.allItems = items
        self.selectedNames = Set(selectedNames)
        self.onSave = onSave

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "选择应用"
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.contentView = buildContentView()
        rebuildList()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func presentSheet(for parentWindow: NSWindow) {
        parentWindow.beginSheet(window!, completionHandler: nil)
    }

    private func buildContentView() -> NSView {
        searchField.placeholderString = "搜索应用名称"
        searchField.target = self
        searchField.action = #selector(searchDidChange(_:))

        listStackView.orientation = .vertical
        listStackView.spacing = 8
        listStackView.alignment = .leading

        let listDocumentView = NSView()
        listDocumentView.addSubview(listStackView)
        listStackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            listStackView.topAnchor.constraint(equalTo: listDocumentView.topAnchor, constant: 12),
            listStackView.leadingAnchor.constraint(equalTo: listDocumentView.leadingAnchor, constant: 12),
            listStackView.trailingAnchor.constraint(equalTo: listDocumentView.trailingAnchor, constant: -12),
            listStackView.bottomAnchor.constraint(equalTo: listDocumentView.bottomAnchor, constant: -12),
            listStackView.widthAnchor.constraint(equalTo: listDocumentView.widthAnchor, constant: -24),
        ])

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = listDocumentView

        let hintLabel = NSTextField(wrappingLabelWithString:
            "优先列出最近检测到的来源，其次是本机 Applications 中的已安装应用。"
        )
        hintLabel.textColor = .secondaryLabelColor

        let saveButton = NSButton(title: "确定", target: self, action: #selector(saveSelection(_:)))
        let cancelButton = NSButton(title: "取消", target: self, action: #selector(cancelSelection(_:)))
        let buttonRow = NSStackView(views: [saveButton, cancelButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        let contentStack = NSStackView(views: [searchField, hintLabel, scrollView, buttonRow])
        contentStack.orientation = .vertical
        contentStack.spacing = 12
        contentStack.alignment = .leading

        let contentView = NSView()
        contentView.addSubview(contentStack)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            scrollView.widthAnchor.constraint(equalToConstant: 440),
            scrollView.heightAnchor.constraint(equalToConstant: 420),
        ])

        return contentView
    }

    private func rebuildList() {
        listStackView.arrangedSubviews.forEach {
            listStackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let query = searchField.stringValue.fingerprint
        let visibleItems = allItems.filter { item in
            query.isEmpty || item.name.fingerprint.contains(query)
        }

        for item in visibleItems {
            let button = NSButton(
                checkboxWithTitle: item.name,
                target: self,
                action: #selector(toggleItem(_:))
            )
            button.state = selectedNames.contains(item.name) ? .on : .off
            button.identifier = NSUserInterfaceItemIdentifier(rawValue: item.name)

            let iconView = NSImageView(image: appIcon(for: item))
            iconView.imageScaling = .scaleProportionallyUpOrDown
            iconView.setFrameSize(NSSize(width: 20, height: 20))

            let subtitle = NSTextField(labelWithString: item.origin == .recent ? "最近检测到" : "已安装应用")
            subtitle.textColor = .secondaryLabelColor
            subtitle.font = .systemFont(ofSize: 11)

            let textStack = NSStackView(views: [button, subtitle])
            textStack.orientation = .vertical
            textStack.spacing = 2
            textStack.alignment = .leading

            let row = NSStackView(views: [iconView, textStack])
            row.orientation = .horizontal
            row.spacing = 8
            row.alignment = .centerY
            listStackView.addArrangedSubview(row)
        }
    }

    private func appIcon(for item: AppCatalogItem) -> NSImage {
        if let path = item.path {
            return NSWorkspace.shared.icon(forFile: path)
        }
        if #available(macOS 12.0, *) {
            return NSWorkspace.shared.icon(for: .application)
        }
        return NSWorkspace.shared.icon(forFileType: "app")
    }

    @objc private func searchDidChange(_ sender: Any?) {
        rebuildList()
    }

    @objc private func toggleItem(_ sender: NSButton) {
        let name = sender.identifier?.rawValue ?? sender.title
        if sender.state == .on {
            selectedNames.insert(name)
        } else {
            selectedNames.remove(name)
        }
    }

    @objc private func saveSelection(_ sender: Any?) {
        onSave(selectedNames.sorted())
        closeSheet()
    }

    @objc private func cancelSelection(_ sender: Any?) {
        closeSheet()
    }

    private func closeSheet() {
        guard let window, let parent = window.sheetParent else {
            close()
            return
        }
        parent.endSheet(window)
    }
}
