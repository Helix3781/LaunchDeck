import AppKit
import Foundation

/// Finds applications in the usual places, without touching the network or the Dock database.
enum AppScanner {

    static let roots: [URL] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true),
        ]
    }()

    static func scan(excluding ownBundleID: String?) -> [AppItem] {
        var found: [String: AppItem] = [:]
        let fm = FileManager.default

        for root in roots {
            guard let entries = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for entry in entries {
                guard entry.pathExtension.lowercased() == "app" else { continue }
                guard let item = makeItem(url: entry, ownBundleID: ownBundleID) else { continue }
                found[item.id] = item
            }
        }

        // A few well-known apps live one level deeper inside /Applications sub-folders.
        if let top = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: "/Applications", isDirectory: true),
                                                 includingPropertiesForKeys: [.isDirectoryKey],
                                                 options: [.skipsHiddenFiles]) {
            for dir in top where dir.pathExtension.isEmpty {
                guard let inner = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil,
                                                              options: [.skipsHiddenFiles]) else { continue }
                for entry in inner where entry.pathExtension.lowercased() == "app" {
                    guard let item = makeItem(url: entry, ownBundleID: ownBundleID) else { continue }
                    found[item.id] = item
                }
            }
        }

        return found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func makeItem(url: URL, ownBundleID: String?) -> AppItem? {
        guard let bundle = Bundle(url: url) else { return nil }
        let info = bundle.infoDictionary ?? [:]
        if (info["CFBundlePackageType"] as? String) != "APPL" { return nil }
        // LSUIElement apps (menu-bar apps like Docker Desktop) stay visible, matching Launchpad;
        // only true background-only agents are excluded.
        if (info["LSBackgroundOnly"] as? Bool) == true { return nil }

        let bundleID = bundle.bundleIdentifier
        if let own = ownBundleID, bundleID == own { return nil }

        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent

        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        let id = bundleID ?? url.resolvingSymlinksInPath().path

        return AppItem(id: id, name: name, url: url, bundleID: bundleID, modified: modified)
    }
}
