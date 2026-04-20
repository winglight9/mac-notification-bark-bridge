import AppKit
import Foundation

@main
struct MacNotificationBarkBridgeMain {
    static func main() async {
        do {
            switch try LaunchMode.resolve() {
            case .menuBar:
                MenuBarAppLauncher.run()
            case .commandLine(let configuration):
                var service = makeBridgeService(configuration: configuration)
                try await service.run()
            }
        } catch let error as BridgeError {
            fputs("error: \(error.description)\n", stderr)
            Foundation.exit(EXIT_FAILURE)
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            Foundation.exit(EXIT_FAILURE)
        }
    }
}
