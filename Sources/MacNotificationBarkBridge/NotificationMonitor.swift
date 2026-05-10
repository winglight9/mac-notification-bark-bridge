import AppKit
@preconcurrency import ApplicationServices
import Foundation
import os

enum AccessibilityPermissionSupport {
    private static let promptState = OSAllocatedUnfairLock(initialState: Date.distantPast)
    private static let promptCooldown: TimeInterval = 15

    static func shouldPrompt(now: Date = Date()) -> Bool {
        promptState.withLock { lastPromptAt in
            guard now.timeIntervalSince(lastPromptAt) >= promptCooldown else {
                return false
            }
            lastPromptAt = now
            return true
        }
    }

    @MainActor
    static func isTrusted(prompt: Bool) -> Bool {
        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }

        return AXIsProcessTrusted()
    }

    @MainActor
    @discardableResult
    static func openSettingsPane() -> Bool {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
        ]

        for rawURL in urls {
            guard let url = URL(string: rawURL) else {
                continue
            }

            if NSWorkspace.shared.open(url) {
                return true
            }
        }

        return false
    }
}

protocol NotificationSnapshotProviding: Sendable {
    func snapshot() async throws -> AccessibilityNode
}

struct AccessibilityNotificationSnapshotProvider: NotificationSnapshotProviding {
    private static let panelVisibilityState = OSAllocatedUnfairLock(initialState: Optional<Bool>.none)
    private let permissionRetryCount = 10
    private let permissionRetryDelayNanoseconds: UInt64 = 300_000_000
    let promptForAccessibility: Bool
    let logger: any BridgeLogging
    let maxDepth: Int
    let maxChildrenPerNode: Int

    init(
        promptForAccessibility: Bool,
        logger: any BridgeLogging = NoopBridgeLogger(),
        maxDepth: Int = 8,
        maxChildrenPerNode: Int = 48
    ) {
        self.promptForAccessibility = promptForAccessibility
        self.logger = logger
        self.maxDepth = maxDepth
        self.maxChildrenPerNode = maxChildrenPerNode
    }

    func snapshot() async throws -> AccessibilityNode {
        try await requireAccessibilityPermission()

        let root = try notificationCenterRoot()
        let windows = arrayValue(for: kAXWindowsAttribute, element: root)
        await logPanelVisibilityIfNeeded(!windows.isEmpty)
        await logWindowDiagnostics(windows, root: root)
        let captured = snapshot(element: root, depth: 0)
        return captured
    }

    private func requireAccessibilityPermission() async throws {
        if await ensureAccessibilityPermission(prompt: false) {
            return
        }

        let shouldPrompt = promptForAccessibility && AccessibilityPermissionSupport.shouldPrompt()

        if await ensureAccessibilityPermission(prompt: shouldPrompt) {
            if shouldPrompt {
                await logger.log(.info, "scan.permission_check prompt=true")
                await logger.log(.info, "scan.permission_prompt_result trusted=true")
            }
            return
        }

        if shouldPrompt {
            await logger.log(.info, "scan.permission_check prompt=true")
            await logger.log(.warning, "scan.permission_prompt_result trusted=false")
            let opened = await MainActor.run {
                AccessibilityPermissionSupport.openSettingsPane()
            }
            await logger.log(.info, "scan.permission_settings_opened success=\(opened)")
        }

        for attempt in 1...permissionRetryCount {
            try? await Task.sleep(nanoseconds: permissionRetryDelayNanoseconds)
            if await ensureAccessibilityPermission(prompt: false) {
                await logger.log(.info, "scan.permission_ready_after_retry attempts=\(attempt)")
                return
            }
        }

        await logger.log(.error, "scan.permission_missing \(currentProcessLogContext())")
        throw BridgeError.accessibilityPermissionDenied
    }

    private func ensureAccessibilityPermission(prompt: Bool) async -> Bool {
        await MainActor.run {
            AccessibilityPermissionSupport.isTrusted(prompt: prompt)
        }
    }

    private func notificationCenterRoot() throws -> AXUIElement {
        if let app = notificationCenterApplication() {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            _ = AXUIElementSetMessagingTimeout(root, 0.2)
            return root
        }

        throw BridgeError.notificationCenterNotRunning
    }

    private func notificationCenterApplication() -> NSRunningApplication? {
        let bundleIdentifiers = [
            "com.apple.notificationcenterui",
            "com.apple.controlcenter",
        ]

        for bundleIdentifier in bundleIdentifiers {
            if let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                .first(where: { !$0.isTerminated }) {
                return application
            }
        }

        return NSWorkspace.shared.runningApplications.first {
            guard let name = $0.localizedName else {
                return false
            }

            return !$0.isTerminated && (name == "NotificationCenter" || name == "控制中心")
        }
    }

    private func logPanelVisibilityIfNeeded(_ isVisible: Bool) async {
        let previousVisibility = Self.panelVisibilityState.withLock { state in
            let previous = state
            state = isVisible
            return previous
        }

        guard previousVisibility != isVisible else {
            return
        }

        await logger.log(.info, "scan.panel_state visible=\(isVisible) autoOpen=false")
    }

    private func logWindowDiagnostics(_ windows: [AXUIElement], root: AXUIElement) async {
        let focusedWindow = elementValue(for: kAXFocusedWindowAttribute, element: root)
        let mainWindow = elementValue(for: kAXMainWindowAttribute, element: root)

        await logger.log(
            .info,
            "scan.windows count=\(windows.count) focused=\(focusedWindow != nil) main=\(mainWindow != nil)"
        )

        for (index, window) in windows.enumerated() {
            let role = stringValue(for: kAXRoleAttribute, element: window) ?? "-"
            let subrole = stringValue(for: kAXSubroleAttribute, element: window) ?? "-"
            let title = sanitizedLogValue(stringValue(for: kAXTitleAttribute, element: window))
            let description = sanitizedLogValue(stringValue(for: kAXDescriptionAttribute, element: window))
            let identifier = sanitizedLogValue(stringValue(for: kAXIdentifierAttribute, element: window))
            let childCount = arrayValue(for: kAXChildrenAttribute, element: window).count
            let isFocused = sameElement(window, focusedWindow)
            let isMain = sameElement(window, mainWindow)

            await logger.log(
                .info,
                "scan.window index=\(index) role=\(role) subrole=\(subrole) title=\(title) desc=\(description) id=\(identifier) children=\(childCount) focused=\(isFocused) main=\(isMain)"
            )
        }
    }

    private func snapshot(element: AXUIElement, depth: Int) -> AccessibilityNode {
        let role = stringValue(for: kAXRoleAttribute, element: element)
        let subrole = stringValue(for: kAXSubroleAttribute, element: element)
        let title = stringValue(for: kAXTitleAttribute, element: element)
        let value = stringValue(for: kAXValueAttribute, element: element)
        let description = stringValue(for: kAXDescriptionAttribute, element: element)
        let identifier = stringValue(for: kAXIdentifierAttribute, element: element)

        let children: [AccessibilityNode]
        if depth >= maxDepth {
            children = []
        } else {
            children = childElements(for: element, depth: depth)
                .prefix(maxChildrenPerNode)
                .map { snapshot(element: $0, depth: depth + 1) }
        }

        return AccessibilityNode(
            role: role,
            subrole: subrole,
            title: title,
            value: value,
            nodeDescription: description,
            identifier: identifier,
            children: children
        )
    }

    private func childElements(for element: AXUIElement, depth: Int) -> [AXUIElement] {
        if depth == 0 {
            let windows = arrayValue(for: kAXWindowsAttribute, element: element)
            if !windows.isEmpty {
                return windows
            }
        }

        let attributes = [kAXChildrenAttribute]

        var allChildren: [AXUIElement] = []
        for attribute in attributes {
            allChildren.append(contentsOf: arrayValue(for: attribute, element: element))
        }

        return allChildren
    }

    private func stringValue(for attribute: String, element: AXUIElement) -> String? {
        var rawValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &rawValue)
        guard error == .success, let rawValue else {
            return nil
        }

        if CFGetTypeID(rawValue) == CFStringGetTypeID() {
            return rawValue as? String
        }

        return nil
    }

    private func arrayValue(for attribute: String, element: AXUIElement) -> [AXUIElement] {
        var rawValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &rawValue)
        guard error == .success, let rawValue else {
            return []
        }

        guard CFGetTypeID(rawValue) == CFArrayGetTypeID(),
              let values = rawValue as? [Any] else {
            return []
        }

        return values.map { $0 as! AXUIElement }
    }

    private func elementValue(for attribute: String, element: AXUIElement) -> AXUIElement? {
        var rawValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &rawValue)
        guard error == .success, let rawValue else {
            return nil
        }

        return rawValue as! AXUIElement?
    }

    private func sameElement(_ lhs: AXUIElement, _ rhs: AXUIElement?) -> Bool {
        guard let rhs else {
            return false
        }

        return CFEqual(lhs, rhs)
    }

    private func sanitizedLogValue(_ value: String?) -> String {
        guard let value else {
            return "-"
        }

        let collapsed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        guard !collapsed.isEmpty else {
            return "-"
        }

        if collapsed.count <= 80 {
            return collapsed
        }

        let endIndex = collapsed.index(collapsed.startIndex, offsetBy: 80)
        return String(collapsed[..<endIndex]) + "..."
    }
}

struct FixtureSnapshotProvider: NotificationSnapshotProviding {
    let path: String

    func snapshot() async throws -> AccessibilityNode {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(AccessibilityNode.self, from: data)
    }
}
