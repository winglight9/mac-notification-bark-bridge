import CoreGraphics
import Foundation

struct Options {
    var tempWidth: Int = 1024
    var tempHeight: Int = 768
    var delay: TimeInterval = 1.0
    var displayIndex: Int = 1
    var listOnly: Bool = false
    var dryRun: Bool = false
    var verbose: Bool = false
    var showHelp: Bool = false
}

enum RefreshError: LocalizedError {
    case usage(String)
    case coreGraphics(String, CGError)
    case noDisplays
    case noExternalDisplays
    case invalidDisplayIndex(Int, Int)
    case noAlternateMode(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message):
            return message
        case .coreGraphics(let operation, let error):
            return "\(operation) failed with CoreGraphics error \(error.rawValue)."
        case .noDisplays:
            return "No online displays were detected."
        case .noExternalDisplays:
            return "No external displays were detected. The script only refreshes external monitors."
        case .invalidDisplayIndex(let requested, let available):
            return "Display index \(requested) is out of range. Available external displays: \(available)."
        case .noAlternateMode(let description):
            return "Could not find a temporary mode different from the current mode for \(description)."
        }
    }
}

struct DisplayInfo {
    let id: CGDirectDisplayID
    let ordinal: Int
    let isMain: Bool
    let isBuiltin: Bool
    let currentMode: CGDisplayMode
    let modes: [CGDisplayMode]

    var label: String {
        let kind = isBuiltin ? "built-in" : "external"
        let mainFlag = isMain ? ", main" : ""
        return "display \(ordinal) (id \(id), \(kind)\(mainFlag))"
    }
}

@main
struct DisplayRefreshTool {
    static func main() {
        do {
            let options = try parseOptions(arguments: Array(CommandLine.arguments.dropFirst()))
            if options.showHelp {
                print(usageText())
                return
            }
            let displays = try loadDisplays()

            if options.listOnly {
                printDisplayList(displays)
                return
            }

            let externalDisplays = displays.filter { !$0.isBuiltin }
            guard !externalDisplays.isEmpty else {
                throw RefreshError.noExternalDisplays
            }

            guard options.displayIndex > 0, options.displayIndex <= externalDisplays.count else {
                throw RefreshError.invalidDisplayIndex(options.displayIndex, externalDisplays.count)
            }

            let targetDisplay = externalDisplays[options.displayIndex - 1]
            let tempMode = try chooseTemporaryMode(
                for: targetDisplay,
                targetWidth: options.tempWidth,
                targetHeight: options.tempHeight
            )

            print("Selected \(targetDisplay.label)")
            print("Current mode: \(describe(mode: targetDisplay.currentMode))")
            print("Temporary mode: \(describe(mode: tempMode))")

            if options.dryRun {
                print("Dry run complete. No display mode changes were applied.")
                return
            }

            if options.verbose {
                print("Switching to temporary mode for \(String(format: "%.2f", options.delay)) seconds...")
            }

            try setDisplayMode(tempMode, for: targetDisplay.id, operation: "Switching to temporary mode")
            Thread.sleep(forTimeInterval: options.delay)
            try setDisplayMode(targetDisplay.currentMode, for: targetDisplay.id, operation: "Restoring original mode")

            print("Display refresh completed.")
        } catch {
            fputs("refresh-external-display: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

private func parseOptions(arguments: [String]) throws -> Options {
    var options = Options()
    var iterator = arguments.makeIterator()

    while let argument = iterator.next() {
        switch argument {
        case "--list":
            options.listOnly = true
        case "--dry-run":
            options.dryRun = true
        case "--verbose":
            options.verbose = true
        case "--temp-width":
            let value = try requireValue(after: argument, from: &iterator)
            guard let parsed = Int(value), parsed > 0 else {
                throw RefreshError.usage("Invalid value for \(argument): \(value)")
            }
            options.tempWidth = parsed
        case "--temp-height":
            let value = try requireValue(after: argument, from: &iterator)
            guard let parsed = Int(value), parsed > 0 else {
                throw RefreshError.usage("Invalid value for \(argument): \(value)")
            }
            options.tempHeight = parsed
        case "--delay":
            let value = try requireValue(after: argument, from: &iterator)
            guard let parsed = Double(value), parsed >= 0 else {
                throw RefreshError.usage("Invalid value for \(argument): \(value)")
            }
            options.delay = parsed
        case "--display-index":
            let value = try requireValue(after: argument, from: &iterator)
            guard let parsed = Int(value), parsed > 0 else {
                throw RefreshError.usage("Invalid value for \(argument): \(value)")
            }
            options.displayIndex = parsed
        case "--help", "-h":
            options.showHelp = true
        default:
            throw RefreshError.usage("Unknown argument: \(argument)\n\n\(usageText())")
        }
    }

    return options
}

private func requireValue(
    after argument: String,
    from iterator: inout IndexingIterator<[String]>
) throws -> String {
    guard let value = iterator.next() else {
        throw RefreshError.usage("Missing value after \(argument)\n\n\(usageText())")
    }
    return value
}

private func usageText() -> String {
    """
    Usage:
      refresh-external-display [options]

    Options:
      --list                   List online displays and current modes.
      --dry-run                Show which modes would be used without switching.
      --temp-width <value>     Temporary width. Default: 1024.
      --temp-height <value>    Temporary height. Default: 768.
      --delay <seconds>        Time to stay on temporary mode. Default: 1.0.
      --display-index <value>  External display index from --list output. Default: 1.
      --verbose                Print extra progress information.
      --help, -h               Show this help.
    """
}

private func loadDisplays() throws -> [DisplayInfo] {
    let maxDisplays: UInt32 = 16
    var activeCount: UInt32 = 0
    var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
    let error = CGGetOnlineDisplayList(maxDisplays, &displayIDs, &activeCount)
    guard error == .success else {
        throw RefreshError.coreGraphics("CGGetOnlineDisplayList", error)
    }

    let onlineDisplayIDs = Array(displayIDs.prefix(Int(activeCount)))
    guard !onlineDisplayIDs.isEmpty else {
        throw RefreshError.noDisplays
    }

    let mainDisplay = CGMainDisplayID()

    return try onlineDisplayIDs.enumerated().map { index, displayID in
        guard let currentMode = CGDisplayCopyDisplayMode(displayID) else {
            throw RefreshError.noDisplays
        }

        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        let availableModes = (CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode]) ?? []

        return DisplayInfo(
            id: displayID,
            ordinal: index + 1,
            isMain: displayID == mainDisplay,
            isBuiltin: CGDisplayIsBuiltin(displayID) != 0,
            currentMode: currentMode,
            modes: availableModes
        )
    }
}

private func printDisplayList(_ displays: [DisplayInfo]) {
    if displays.isEmpty {
        print("No displays detected.")
        return
    }

    for display in displays {
        print("\(display.label)")
        print("  current: \(describe(mode: display.currentMode))")

        let distinctModes = uniqueModes(display.modes)
        let preview = distinctModes.prefix(6).map { describe(mode: $0) }.joined(separator: " | ")
        if preview.isEmpty {
            print("  available: none reported")
        } else {
            let suffix = distinctModes.count > 6 ? " | ..." : ""
            print("  available: \(preview)\(suffix)")
        }
    }
}

private func chooseTemporaryMode(
    for display: DisplayInfo,
    targetWidth: Int,
    targetHeight: Int
) throws -> CGDisplayMode {
    let current = display.currentMode
    let alternatives = uniqueModes(display.modes).filter { !modesEqual($0, current) }

    if let exactMatch = alternatives
        .filter({ Int($0.width) == targetWidth && Int($0.height) == targetHeight })
        .sorted(by: { score(mode: $0, targetWidth: targetWidth, targetHeight: targetHeight, current: current) >
            score(mode: $1, targetWidth: targetWidth, targetHeight: targetHeight, current: current) })
        .first {
        return exactMatch
    }

    if let nearestMatch = alternatives.max(by: {
        score(mode: $0, targetWidth: targetWidth, targetHeight: targetHeight, current: current) <
        score(mode: $1, targetWidth: targetWidth, targetHeight: targetHeight, current: current)
    }) {
        return nearestMatch
    }

    throw RefreshError.noAlternateMode(display.label)
}

private func score(
    mode: CGDisplayMode,
    targetWidth: Int,
    targetHeight: Int,
    current: CGDisplayMode
) -> Int {
    var value = 0

    let delta = abs(Int(mode.width) - targetWidth) + abs(Int(mode.height) - targetHeight)
    value -= delta * 10

    if Int(mode.width) == targetWidth && Int(mode.height) == targetHeight {
        value += 100_000
    }

    if abs(mode.refreshRate - current.refreshRate) < 0.5 {
        value += 200
    }

    let currentPixels = Int(current.pixelWidth * current.pixelHeight)
    let modePixels = Int(mode.pixelWidth * mode.pixelHeight)
    if modePixels < currentPixels {
        value += 100
    }

    if Int(mode.width) <= Int(current.width) && Int(mode.height) <= Int(current.height) {
        value += 50
    }

    return value
}

private func uniqueModes(_ modes: [CGDisplayMode]) -> [CGDisplayMode] {
    var seen = Set<String>()
    var result: [CGDisplayMode] = []

    for mode in modes {
        let key = modeIdentity(mode)
        if seen.insert(key).inserted {
            result.append(mode)
        }
    }

    return result
}

private func modeIdentity(_ mode: CGDisplayMode) -> String {
    [
        String(mode.width),
        String(mode.height),
        String(mode.pixelWidth),
        String(mode.pixelHeight),
        String(format: "%.2f", mode.refreshRate),
        String(mode.ioFlags)
    ].joined(separator: ":")
}

private func modesEqual(_ lhs: CGDisplayMode, _ rhs: CGDisplayMode) -> Bool {
    modeIdentity(lhs) == modeIdentity(rhs)
}

private func describe(mode: CGDisplayMode) -> String {
    let size = "\(mode.width)x\(mode.height)"
    let pixels = "\(mode.pixelWidth)x\(mode.pixelHeight)"
    let refreshRate = mode.refreshRate > 0 ? String(format: "@ %.2fHz", mode.refreshRate) : "@ defaultHz"
    return "\(size) (pixels \(pixels) \(refreshRate))"
}

private func setDisplayMode(_ mode: CGDisplayMode, for displayID: CGDirectDisplayID, operation: String) throws {
    let error = CGDisplaySetDisplayMode(displayID, mode, nil)
    guard error == .success else {
        throw RefreshError.coreGraphics(operation, error)
    }
}
