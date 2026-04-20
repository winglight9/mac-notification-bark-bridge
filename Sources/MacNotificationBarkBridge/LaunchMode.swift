import Foundation

enum LaunchMode {
    case menuBar
    case commandLine(AppConfiguration)

    static func resolve(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> LaunchMode {
        let userArguments = Array(arguments.dropFirst())
        let usesMenuBarFlag = userArguments.contains("--menu-bar")

        if usesMenuBarFlag && userArguments.count > 1 {
            throw BridgeError.invalidOption("--menu-bar")
        }

        if userArguments.isEmpty || usesMenuBarFlag {
            return .menuBar
        }

        return .commandLine(
            try AppConfiguration.parse(arguments: arguments, environment: environment)
        )
    }
}
