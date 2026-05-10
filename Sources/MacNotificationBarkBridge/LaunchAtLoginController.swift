import Foundation
import ServiceManagement

@MainActor
enum LaunchAtLoginController {
    static var isAvailable: Bool {
        if #available(macOS 13.0, *) {
            return true
        }
        return false
    }

    static var isEnabled: Bool {
        guard #available(macOS 13.0, *) else {
            return false
        }

        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            return true
        case .notFound, .notRegistered:
            return false
        @unknown default:
            return false
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else {
            throw BridgeError.launchAtLoginUnavailable
        }

        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
