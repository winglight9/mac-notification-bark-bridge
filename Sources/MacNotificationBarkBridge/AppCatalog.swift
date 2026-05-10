import AppKit
import Foundation
import UniformTypeIdentifiers

struct AppCatalogItem: Hashable, Sendable, Identifiable {
    enum Origin: String, Sendable {
        case installed
        case recent
    }

    let id: String
    let name: String
    let path: String?
    let origin: Origin
}

struct AppCatalog {
    let diagnosticsStore: DiagnosticsStore

    init(diagnosticsStore: DiagnosticsStore = DiagnosticsStore()) {
        self.diagnosticsStore = diagnosticsStore
    }

    func loadItems() -> [AppCatalogItem] {
        let installed = installedApplications()
        let recent = recentNotificationSources(excluding: Set(installed.map { $0.name.fingerprint }))

        return (recent + installed).sorted { lhs, rhs in
            if lhs.origin != rhs.origin {
                return lhs.origin == .recent
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    @MainActor
    func icon(for item: AppCatalogItem) -> NSImage {
        if let path = item.path {
            return NSWorkspace.shared.icon(forFile: path)
        }

        if #available(macOS 12.0, *) {
            return NSWorkspace.shared.icon(for: .application)
        }
        return NSWorkspace.shared.icon(forFileType: "app")
    }

    private func installedApplications() -> [AppCatalogItem] {
        let searchRoots = [
            "/Applications",
            "/System/Applications",
            NSString(string: "~/Applications").expandingTildeInPath,
        ]

        var seen = Set<String>()
        var items: [AppCatalogItem] = []
        let fileManager = FileManager.default

        for root in searchRoots {
            guard let enumerator = fileManager.enumerator(
                at: URL(fileURLWithPath: root, isDirectory: true),
                includingPropertiesForKeys: [.isApplicationKey, .nameKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "app" else {
                    continue
                }

                let name = appDisplayName(for: url)
                let key = name.fingerprint
                guard !key.isEmpty, seen.insert(key).inserted else {
                    continue
                }

                items.append(
                    AppCatalogItem(
                        id: "installed-\(key)",
                        name: name,
                        path: url.path,
                        origin: .installed
                    )
                )
            }
        }

        return items
    }

    private func recentNotificationSources(excluding excluded: Set<String>) -> [AppCatalogItem] {
        guard let snapshotURL = try? diagnosticsStore.latestSnapshotURL(),
              FileManager.default.fileExists(atPath: snapshotURL.path),
              let data = try? Data(contentsOf: snapshotURL),
              let root = try? JSONDecoder().decode(AccessibilityNode.self, from: data) else {
            return []
        }

        let sources = NotificationParser()
            .parse(from: root, sourceFilter: nil)
            .map(\.source)
            .stableUniqued()

        return sources.compactMap { source in
            let key = source.fingerprint
            guard !key.isEmpty, !excluded.contains(key) else {
                return nil
            }

            return AppCatalogItem(
                id: "recent-\(key)",
                name: source,
                path: nil,
                origin: .recent
            )
        }
    }

    private func appDisplayName(for url: URL) -> String {
        let bundle = Bundle(url: url)
        return bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
    }
}
