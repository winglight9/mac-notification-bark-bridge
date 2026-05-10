import AppKit
import Foundation

@MainActor
final class MenuBarAppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let configurationStore = ConfigurationStore()
    private let diagnosticsStore = DiagnosticsStore()
    private let logger = FileBridgeLogger()
    private lazy var idleScreenDimmingController = IdleScreenDimmingController(logger: logger)
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private let versionMenuItem = NSMenuItem(title: "版本：--", action: nil, keyEquivalent: "")
    private let statusMenuItem = NSMenuItem(title: "状态：启动中…", action: nil, keyEquivalent: "")
    private let detailMenuItem = NSMenuItem(title: "正在初始化", action: nil, keyEquivalent: "")
    private let configMenuItem = NSMenuItem(title: "配置：未知", action: nil, keyEquivalent: "")
    private lazy var startStopMenuItem = NSMenuItem(
        title: "停止监听",
        action: #selector(toggleMonitoring(_:)),
        keyEquivalent: ""
    )
    private lazy var scanNowMenuItem = NSMenuItem(
        title: "立即扫描",
        action: #selector(scanNow(_:)),
        keyEquivalent: ""
    )
    private lazy var reloadConfigMenuItem = NSMenuItem(
        title: "重新加载配置",
        action: #selector(reloadConfigurationFromMenu(_:)),
        keyEquivalent: ""
    )
    private lazy var settingsMenuItem = NSMenuItem(
        title: "设置…",
        action: #selector(openSettingsWindow(_:)),
        keyEquivalent: ","
    )
    private lazy var accessibilityMenuItem = NSMenuItem(
        title: "授权辅助功能…",
        action: #selector(requestAccessibilityAccess(_:)),
        keyEquivalent: ""
    )
    private lazy var openConfigMenuItem = NSMenuItem(
        title: "打开配置目录",
        action: #selector(openConfigurationDirectory(_:)),
        keyEquivalent: ""
    )
    private lazy var openLogMenuItem = NSMenuItem(
        title: "打开日志文件",
        action: #selector(openLogFile(_:)),
        keyEquivalent: ""
    )
    private lazy var openSnapshotMenuItem = NSMenuItem(
        title: "打开最近快照",
        action: #selector(openLatestSnapshot(_:)),
        keyEquivalent: ""
    )
    private lazy var quitMenuItem = NSMenuItem(
        title: "退出",
        action: #selector(quit(_:)),
        keyEquivalent: "q"
    )

    private var configuration: AppConfiguration?
    private var service: BridgeService?
    private var pollingTask: Task<Void, Never>?
    private var configurationWindowController: ConfigurationWindowController?
    private var isMonitoringEnabled = true
    private var didPresentSetupNotice = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        configureMenu()
        Task {
            await logger.log(.info, "app.launch \(currentProcessLogContext())")
        }
        refreshConfiguration(startMonitoring: true)
        presentSetupNoticeIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollingTask?.cancel()
        idleScreenDimmingController.stop()
        Task {
            await logger.log(.info, "app.terminate")
        }
    }

    private func configureMenu() {
        versionMenuItem.isEnabled = false
        statusMenuItem.isEnabled = false
        detailMenuItem.isEnabled = false
        configMenuItem.isEnabled = false

        versionMenuItem.title = "版本：\(appVersionString())"

        let menu = NSMenu()
        menu.addItem(versionMenuItem)
        menu.addItem(statusMenuItem)
        menu.addItem(detailMenuItem)
        menu.addItem(configMenuItem)
        menu.addItem(.separator())
        menu.addItem(startStopMenuItem)
        menu.addItem(scanNowMenuItem)
        menu.addItem(settingsMenuItem)
        menu.addItem(accessibilityMenuItem)
        menu.addItem(reloadConfigMenuItem)
        menu.addItem(openConfigMenuItem)
        menu.addItem(openLogMenuItem)
        menu.addItem(openSnapshotMenuItem)
        menu.addItem(.separator())
        menu.addItem(quitMenuItem)

        statusItem.menu = menu
        updateAppearance(symbolName: "bell.badge", tooltip: "Mac 通知 Bark 转发")
    }

    private func refreshConfiguration(startMonitoring: Bool) {
        do {
            let configURL = try configurationStore.ensureConfigurationFileExists()
            let displayPath = NSString(string: configURL.path).abbreviatingWithTildeInPath
            configMenuItem.title = "配置：\(displayPath)"

            let configuration = try configurationStore.load()
            self.configuration = configuration
            Task {
                await logger.updateRetentionDays(configuration.diagnosticsRetentionDays)
            }
            self.service = makeBridgeService(configuration: configuration, logger: logger)
            idleScreenDimmingController.apply(configuration: configuration)

            let filterText = configuration.monitoredApplicationsDescription
            updateStatus(
                title: "状态：就绪",
                detail: "规则 \(configuration.rules.count) 条，监听：\(filterText)"
            )
            Task {
                await logger.log(
                    .info,
                    "app.config_loaded rules=\(configuration.rules.count) monitoredApps=\(filterText) pollInterval=\(configuration.pollInterval) dryRun=\(configuration.dryRun)"
                )
            }

            if startMonitoring && isMonitoringEnabled {
                startMonitoringLoop()
            }
        } catch {
            configuration = nil
            service = nil
            idleScreenDimmingController.stop()
            stopMonitoringLoop()
            updateErrorStatus(error)
            Task {
                await logger.log(.error, "app.config_failed error=\(describe(error))")
            }
        }
    }

    private func startMonitoringLoop() {
        guard pollingTask == nil else {
            return
        }

        guard service != nil else {
            refreshConfiguration(startMonitoring: true)
            return
        }

        isMonitoringEnabled = true
        startStopMenuItem.title = "停止监听"
        updateAppearance(symbolName: "bell.badge.fill", tooltip: "正在监听通知")

        pollingTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    private func stopMonitoringLoop() {
        pollingTask?.cancel()
        pollingTask = nil
        startStopMenuItem.title = "开始监听"

        if configuration != nil {
            updateAppearance(symbolName: "bell.slash", tooltip: "监听已暂停")
        }
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            do {
                let notifications = try await runCycle()
                let timestamp = timeFormatter.string(from: Date())

                if notifications.isEmpty {
                    updateStatus(
                        title: "状态：监听中",
                        detail: "最近扫描：\(timestamp)"
                    )
                } else {
                    let action = configuration?.dryRun == true ? "匹配到" : "已转发"
                    updateStatus(
                        title: "状态：监听中",
                        detail: "\(action) \(notifications.count) 条通知，时间：\(timestamp)"
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                updateErrorStatus(error)
            }

            guard let interval = configuration?.pollInterval else {
                return
            }

            do {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            } catch {
                return
            }
        }
    }

    private func runCycle() async throws -> [ForwardedNotification] {
        guard var service else {
            return []
        }

        let notifications = try await service.runOnce()
        self.service = service
        return notifications
    }

    private func updateStatus(title: String, detail: String) {
        statusMenuItem.title = title
        detailMenuItem.title = detail

        if configuration != nil && pollingTask != nil {
            updateAppearance(symbolName: "bell.badge.fill", tooltip: detail)
        }
    }

    private func updateErrorStatus(_ error: Error) {
        let message: String
        if let bridgeError = error as? BridgeError {
            message = bridgeError.description
        } else {
            message = error.localizedDescription
        }

        statusMenuItem.title = "状态：需要处理"
        detailMenuItem.title = message
        updateAppearance(symbolName: "exclamationmark.triangle.fill", tooltip: message)
    }

    private func updateAppearance(symbolName: String, tooltip: String) {
        guard let button = statusItem.button else {
            return
        }

        if let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "Mac Notification Bark Bridge"
        ) {
            image.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = "转发"
        }

        button.toolTip = tooltip
    }

    private func appVersionString() -> String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (shortVersion, buildVersion) {
        case let (short?, build?) where !short.isEmpty && !build.isEmpty:
            return "\(short) (\(build))"
        case let (short?, _ ) where !short.isEmpty:
            return short
        case let (_, build?) where !build.isEmpty:
            return build
        default:
            return "未知"
        }
    }

    @objc private func toggleMonitoring(_ sender: Any?) {
        isMonitoringEnabled.toggle()

        if isMonitoringEnabled {
            refreshConfiguration(startMonitoring: true)
        } else {
            stopMonitoringLoop()
            updateStatus(title: "状态：已暂停", detail: "通知监听已暂停")
            Task {
                await logger.log(.info, "app.monitoring_paused")
            }
        }
    }

    @objc private func scanNow(_ sender: Any?) {
        Task { [weak self] in
            guard let self else {
                return
            }

            if self.service == nil {
                self.refreshConfiguration(startMonitoring: false)
            }

            do {
                let notifications = try await self.runCycle()
                let timestamp = self.timeFormatter.string(from: Date())
                if notifications.isEmpty {
                    self.updateStatus(
                        title: "状态：就绪",
                        detail: "手动扫描未发现通知，时间：\(timestamp)"
                    )
                } else {
                    let action = self.configuration?.dryRun == true ? "匹配到" : "已转发"
                    self.updateStatus(
                        title: "状态：就绪",
                        detail: "\(action) \(notifications.count) 条通知，时间：\(timestamp)"
                    )
                }
            } catch {
                self.updateErrorStatus(error)
            }
        }
    }

    @objc private func reloadConfigurationFromMenu(_ sender: Any?) {
        refreshConfiguration(startMonitoring: isMonitoringEnabled)
    }

    @objc private func openSettingsWindow(_ sender: Any?) {
        if configurationWindowController == nil {
            configurationWindowController = ConfigurationWindowController(
                configurationStore: configurationStore,
                onSave: { [weak self] in
                    guard let self else {
                        return
                    }
                    self.refreshConfiguration(startMonitoring: self.isMonitoringEnabled)
                },
                onClose: { [weak self] in
                    self?.configurationWindowController = nil
                }
            )
        }

        configurationWindowController?.present()
    }

    @objc private func requestAccessibilityAccess(_ sender: Any?) {
        Task { [weak self] in
            guard let self else {
                return
            }

            let trusted = await MainActor.run {
                AccessibilityPermissionSupport.isTrusted(prompt: true)
            }
            await self.logger.log(.info, "app.accessibility_request trusted=\(trusted)")

            if trusted {
                self.updateStatus(
                    title: "状态：就绪",
                    detail: "辅助功能权限已授权"
                )
                return
            }

            let opened = await MainActor.run {
                AccessibilityPermissionSupport.openSettingsPane()
            }
            await self.logger.log(.info, "app.accessibility_settings_opened success=\(opened)")
            self.updateStatus(
                title: "状态：需要处理",
                detail: opened
                    ? "请在辅助功能设置中启用此应用"
                    : "请在系统设置中为此应用启用辅助功能"
            )
        }
    }

    @objc private func openConfigurationDirectory(_ sender: Any?) {
        do {
            let url = try configurationStore.configurationDirectoryURL()
            NSWorkspace.shared.open(url)
        } catch {
            updateErrorStatus(error)
        }
    }

    @objc private func openLogFile(_ sender: Any?) {
        do {
            try diagnosticsStore.ensureLogsDirectoryExists()
            let url = try diagnosticsStore.logFileURL()
            if !FileManager.default.fileExists(atPath: url.path) {
                try "".write(to: url, atomically: true, encoding: .utf8)
            }
            NSWorkspace.shared.open(url)
        } catch {
            updateErrorStatus(error)
        }
    }

    @objc private func openLatestSnapshot(_ sender: Any?) {
        do {
            let url = try diagnosticsStore.latestSnapshotURL()
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw BridgeError.invalidConfigurationFile(
                    path: url.path,
                    reason: "还没有生成快照，请先执行一次“立即扫描”。"
                )
            }
            NSWorkspace.shared.open(url)
        } catch {
            updateErrorStatus(error)
        }
    }

    @objc private func quit(_ sender: Any?) {
        NSApplication.shared.terminate(nil)
    }

    private func presentSetupNoticeIfNeeded() {
        guard !didPresentSetupNotice else {
            return
        }
        didPresentSetupNotice = true

        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "didShowCustomBuildNotice") == false else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "首次使用提示"
        alert.informativeText = """
        这是自定义构建的应用，可能没有经过 Apple 公证。首次安装或替换新版本后，若系统阻止打开，请在 Finder 中右键应用选择“打开”，或到“系统设置 > 隐私与安全性”里手动放行。

        此外，本应用需要辅助功能权限才能读取通知中心内容。
        Bark 设备 Key 等高级项建议直接编辑配置文件；设置窗口更适合调整监听规则和常用开关。
        """
        alert.addButton(withTitle: "知道了")
        alert.runModal()
        defaults.set(true, forKey: "didShowCustomBuildNotice")
    }
}

enum MenuBarAppLauncher {
    @MainActor private static var retainedDelegate: MenuBarAppDelegate?

    @MainActor
    static func run() {
        let app = NSApplication.shared
        let delegate = MenuBarAppDelegate()
        retainedDelegate = delegate
        app.delegate = delegate
        app.run()
    }
}
