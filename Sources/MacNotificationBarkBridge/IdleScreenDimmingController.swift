import AppKit
import CoreGraphics
import Foundation

@MainActor
final class IdleScreenDimmingController {
    private let logger: any BridgeLogging
    private var task: Task<Void, Never>?
    private var overlayWindows: [NSWindow] = []
    private var eventMonitors: [Any] = []
    private var isEnabled = false
    private var isDimmed = false
    private var idleDelay: TimeInterval = 600
    private var overlayOpacity: Double = 1.0
    private var lastUserActivityAt = Date()

    init(logger: any BridgeLogging) {
        self.logger = logger
    }

    func apply(configuration: AppConfiguration?) {
        guard let configuration, configuration.idleScreenDimmingEnabled else {
            stop()
            Task { await logger.log(.info, "app.idle_dimming enabled=false") }
            return
        }

        isEnabled = true
        idleDelay = configuration.idleScreenDimmingDelay
        overlayOpacity = min(max(configuration.idleScreenDimmingOpacity, 0), 1)
        lastUserActivityAt = Date()
        installEventMonitorsIfNeeded()

        Task {
            await logger.log(
                .info,
                "app.idle_dimming enabled=true delay=\(idleDelay) opacity=\(overlayOpacity)"
            )
        }

        guard task == nil else {
            return
        }

        task = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func stop() {
        isEnabled = false
        task?.cancel()
        task = nil
        removeEventMonitors()
        setDimmed(false, idleSeconds: 0)
    }

    private func runLoop() async {
        while !Task.isCancelled {
            let idleSeconds = min(
                CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null),
                Date().timeIntervalSince(lastUserActivityAt)
            )
            let shouldDim = isEnabled && idleSeconds >= idleDelay

            if shouldDim != isDimmed {
                setDimmed(shouldDim, idleSeconds: idleSeconds)
            }

            do {
                try await Task.sleep(nanoseconds: 200_000_000)
            } catch {
                return
            }
        }
    }

    private func installEventMonitorsIfNeeded() {
        guard eventMonitors.isEmpty else {
            return
        }

        let mask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .scrollWheel,
            .keyDown,
            .flagsChanged,
        ]

        if let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            Task { @MainActor in
                self?.handleUserActivity()
            }
        }) {
            eventMonitors.append(globalMonitor)
        }

        if let localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handleUserActivity()
            return event
        }) {
            eventMonitors.append(localMonitor)
        }
    }

    private func removeEventMonitors() {
        eventMonitors.forEach { monitor in
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()
    }

    private func handleUserActivity() {
        lastUserActivityAt = Date()

        guard isDimmed else {
            return
        }

        setDimmed(false, idleSeconds: 0)
    }

    private func setDimmed(_ dimmed: Bool, idleSeconds: TimeInterval) {
        guard dimmed != isDimmed else {
            return
        }

        isDimmed = dimmed

        if dimmed {
            NSCursor.hide()
            overlayWindows = NSScreen.screens.map { screen in
                let window = NSWindow(
                    contentRect: screen.frame,
                    styleMask: .borderless,
                    backing: .buffered,
                    defer: false,
                    screen: screen
                )
                window.isReleasedWhenClosed = false
                window.backgroundColor = NSColor.black.withAlphaComponent(overlayOpacity)
                window.isOpaque = overlayOpacity >= 1.0
                window.level = .screenSaver
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
                window.ignoresMouseEvents = true
                window.orderFrontRegardless()
                return window
            }

            Task {
                await logger.log(.info, "app.idle_dimming dimmed=true idleSeconds=\(Int(idleSeconds))")
            }
        } else {
            NSCursor.unhide()
            overlayWindows.forEach { window in
                window.orderOut(nil)
                window.close()
            }
            overlayWindows.removeAll()

            Task {
                await logger.log(.info, "app.idle_dimming dimmed=false idleSeconds=\(Int(idleSeconds))")
            }
        }
    }
}
