import AppKit
import Combine
import Foundation
import ServiceManagement

extension Notification.Name {
    static let launchDeckShouldClose = Notification.Name("LaunchDeckShouldClose")
    static let launchDeckFocusSearch = Notification.Name("LaunchDeckFocusSearch")
    static let launchDeckOpenSettings = Notification.Name("LaunchDeckOpenSettings")
    static let launchDeckRestart = Notification.Name("LaunchDeckRestart")
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var apps: [AppItem] = []
    @Published private(set) var icons: [String: NSImage] = [:]
    @Published private(set) var hidden: Set<String> = []
    @Published private(set) var usage: [String: Usage] = [:]
    @Published private(set) var folders: [AppFolder] = []
    @Published private(set) var isScanning = false

    @Published var settings: Settings {
        didSet { persistSettings(); clampSelection() }
    }

    @Published var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            if !query.isEmpty { openFolderID = nil }
            selection = 0
            page = 0
        }
    }

    @Published var selection: Int = 0
    @Published var page: Int = 0
    @Published var openFolderID: String?
    @Published var panelVisible = false
    @Published var pageDirection = 1
    @Published var launchingID: String?
    @Published var pendingUninstall: AppItem?
    @Published var isUninstalling = false
    @Published var userAlert: UserAlert?
    @Published var renamingFolderID: String?
    @Published var renamingText: String = ""

    private var order: [String] = []
    private let supportDir: URL
    private let layoutURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        supportDir = base.appendingPathComponent("LaunchDeck", isDirectory: true)
        layoutURL = supportDir.appendingPathComponent("layout.json")
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        settings = Self.readSettings()
    }

    // MARK: - Derived data

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var perPage: Int { max(1, settings.columns * settings.rows) }

    private var appMap: [String: AppItem] {
        Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Top-level grid entries: apps and folders, ordered, filtered and sorted.
    private var topLevelEntries: [LauncherEntry] {
        let map = appMap
        let folderMap = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var entries: [LauncherEntry] = []
        var seen = Set<String>()

        for id in order {
            if let folder = folderMap[id] {
                let live = folder.appIDs.filter { map[$0] != nil && !hidden.contains($0) }
                guard !live.isEmpty else { continue }
                var visible = folder
                visible.appIDs = live
                entries.append(.folder(visible))
                seen.insert(id)
            } else if let app = map[id], !hidden.contains(id), !seen.contains(id) {
                entries.append(.app(app))
                seen.insert(id)
            }
        }

        let inFolders = Set(folders.flatMap { $0.appIDs })
        for app in apps where !seen.contains(app.id) && !hidden.contains(app.id) && !inFolders.contains(app.id) {
            entries.append(.app(app))
        }

        switch settings.sortMode {
        case .custom:
            break
        case .name, .mostUsed, .newest:
            var appsOnly: [AppItem] = []
            var foldersOnly: [LauncherEntry] = []
            for entry in entries {
                switch entry {
                case .app(let app): appsOnly.append(app)
                case .folder: foldersOnly.append(entry)
                }
            }
            appsOnly.sort { compare($0, $1) }
            entries = appsOnly.map { .app($0) } + foldersOnly
        }
        return entries
    }

    private func compare(_ lhs: AppItem, _ rhs: AppItem) -> Bool {
        switch settings.sortMode {
        case .name, .custom:
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        case .mostUsed:
            let a = usage[lhs.id]?.count ?? 0
            let b = usage[rhs.id]?.count ?? 0
            if a != b { return a > b }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        case .newest:
            if lhs.modified != rhs.modified { return lhs.modified > rhs.modified }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// What the grid currently shows: all entries, or search hits (apps from folders included).
    var visibleItems: [LauncherEntry] {
        guard isSearching else { return topLevelEntries }
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        var matches: [AppItem] = []
        for app in apps {
            if hidden.contains(app.id) && !settings.showHiddenInSearch { continue }
            let nameHit = app.name.lowercased().contains(needle)
            let idHit = app.bundleID?.lowercased().contains(needle) ?? false
            if nameHit || idHit { matches.append(app) }
        }
        matches.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return matches.map { .app($0) }
    }

    var pages: [[LauncherEntry]] {
        let list = visibleItems
        var chunks: [[LauncherEntry]] = []
        var index = 0
        while index < list.count {
            let end = min(index + perPage, list.count)
            chunks.append(Array(list[index ..< end]))
            index = end
        }
        return chunks.isEmpty ? [[]] : chunks
    }

    var pageCount: Int { pages.count }

    var currentPageItems: [LauncherEntry] {
        let all = pages
        guard !all.isEmpty else { return [] }
        return all[min(max(0, page), all.count - 1)]
    }

    var selectedEntry: LauncherEntry? {
        let all = visibleItems
        guard selection >= 0, selection < all.count else { return nil }
        return all[selection]
    }

    var selectedApp: AppItem? { selectedEntry?.appItem }

    var openFolder: AppFolder? {
        guard let id = openFolderID,
              let folder = folders.first(where: { $0.id == id }) else { return nil }
        let map = appMap
        var copy = folder
        copy.appIDs = folder.appIDs.filter { map[$0] != nil }
        return copy.appIDs.isEmpty ? nil : copy
    }

    func folderApps(_ folder: AppFolder) -> [AppItem] {
        let map = appMap
        return folder.appIDs.compactMap { map[$0] }
    }

    func folderPreviewIcons(_ folder: AppFolder) -> [NSImage?] {
        folderApps(folder).prefix(4).map { icons[$0.id] }
    }

    // MARK: - Loading

    func load() {
        readLayout()
        rescan()
    }

    func rescan() {
        guard !isScanning else { return }
        isScanning = true
        let own = Bundle.main.bundleIdentifier
        Task.detached(priority: .userInitiated) {
            let scanned = AppScanner.scan(excluding: own)
            await MainActor.run {
                self.apps = scanned
                self.isScanning = false
                self.reconcile()
                self.loadIcons()
                self.clampSelection()
            }
        }
    }

    private func readLayout() {
        guard let data = try? Data(contentsOf: layoutURL),
              let file = try? JSONDecoder().decode(LayoutFile.self, from: data) else { return }
        order = file.order
        hidden = Set(file.hidden)
        usage = file.usage
        folders = file.folders
    }

    private func reconcile() {
        let live = Set(apps.map(\.id))
        var seen = Set<String>()
        order = order.filter { entry in
            guard seen.insert(entry).inserted else { return false }
            if entry.hasPrefix("folder.") { return folders.contains { $0.id == entry } }
            return live.contains(entry)
        }

        folders = folders.compactMap { folder in
            var copy = folder
            copy.appIDs = folder.appIDs.filter { live.contains($0) }
            return copy.appIDs.isEmpty ? nil : copy
        }

        let known = Set(order)
        let folderMembers = Set(folders.flatMap { $0.appIDs })
        let leftovers = apps.map(\.id).filter { !known.contains($0) && !folderMembers.contains($0) }
        order.append(contentsOf: leftovers)

        hidden = hidden.intersection(live)
        if let open = openFolderID, !folders.contains(where: { $0.id == open }) {
            openFolderID = nil
        }
        saveLayout()
    }

    private func loadIcons() {
        let missing = apps.filter { icons[$0.id] == nil }
        guard !missing.isEmpty else { return }
        Task.detached(priority: .utility) {
            var loaded: [String: NSImage] = [:]
            for item in missing {
                let image = NSWorkspace.shared.icon(forFile: item.url.path)
                image.size = NSSize(width: 256, height: 256)
                loaded[item.id] = image
            }
            await MainActor.run {
                self.icons.merge(loaded) { current, _ in current }
            }
        }
    }

    func icon(for id: String) -> NSImage? { icons[id] }

    // MARK: - Persistence

    private func persistSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: "launchdeck.settings")
    }

    private static func readSettings() -> Settings {
        guard let data = UserDefaults.standard.data(forKey: "launchdeck.settings"),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else {
            return Settings()
        }
        return settings
    }

    private func saveLayout() {
        let file = LayoutFile(order: order, hidden: Array(hidden), usage: usage, folders: folders)
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: layoutURL, options: .atomic)
    }

    @discardableResult
    func exportLayout(to url: URL) -> Bool {
        let file = LayoutFile(order: order, hidden: Array(hidden), usage: usage, folders: folders)
        guard let data = try? JSONEncoder().encode(file) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    @discardableResult
    func importLayout(from url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(LayoutFile.self, from: data) else { return false }
        order = file.order
        hidden = Set(file.hidden)
        usage = file.usage
        folders = file.folders
        openFolderID = nil
        reconcile()
        saveLayout()
        clampSelection()
        return true
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            settings.launchAtLogin = enabled
        } catch {
            presentAlert("无法修改登录项", error.localizedDescription)
            settings.launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }

    // MARK: - Opening

    func activate(_ entry: LauncherEntry) {
        switch entry {
        case .app(let item): launch(item)
        case .folder(let folder): openFolderID = folder.id
        }
    }

    func activateSelected() {
        if let entry = selectedEntry { activate(entry) }
    }

    func launch(_ item: AppItem) {
        guard launchingID == nil else { return }

        var entry = usage[item.id] ?? Usage()
        entry.count += 1
        entry.last = Date()
        usage[item.id] = entry
        saveLayout()

        // Let the icon zoom towards the viewer before the panel goes away.
        launchingID = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            self.launchingID = nil
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: item.url, configuration: configuration) { _, error in
                if let error {
                    NSLog("LaunchDeck: failed to open %@: %@", item.url.path, error.localizedDescription)
                }
            }
            self.openFolderID = nil
            NotificationCenter.default.post(name: .launchDeckShouldClose, object: nil)
        }
    }

    func reveal(_ item: AppItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func closeFolder() { openFolderID = nil }

    // MARK: - Hiding & uninstalling

    func hideFromLauncher(_ item: AppItem) {
        hidden.insert(item.id)
        saveLayout()
        clampSelection()
    }

    func unhideAll() {
        hidden.removeAll()
        saveLayout()
    }

    func hideRunningApp(_ item: AppItem) {
        NSRunningApplication.runningApplications(withBundleIdentifier: item.bundleID ?? "")
            .first?.hide()
    }

    func quitRunningApp(_ item: AppItem) {
        NSRunningApplication.runningApplications(withBundleIdentifier: item.bundleID ?? "")
            .first?.terminate()
    }

    func isRunning(_ item: AppItem) -> Bool {
        guard let id = item.bundleID else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
    }

    func isSystemApp(_ item: AppItem) -> Bool {
        let path = item.url.path
        return path.hasPrefix("/System/") || path.hasPrefix("/Library/") || path.hasPrefix("/usr/")
    }

    /// Asks for confirmation; the actual trash happens off the main thread in `confirmUninstall`.
    func uninstall(_ item: AppItem, confirm: Bool = true) {
        guard !isSystemApp(item) else {
            userAlert = UserAlert(title: "无法卸载系统应用",
                                  message: "“\(item.name)” 属于 macOS，不能移到废纸篓。")
            return
        }
        if confirm {
            pendingUninstall = item
        } else {
            performUninstall(item)
        }
    }

    func cancelUninstall() {
        pendingUninstall = nil
    }

    func confirmUninstall() {
        guard let item = pendingUninstall else { return }
        pendingUninstall = nil
        performUninstall(item)
    }

    private func performUninstall(_ item: AppItem) {
        guard !isUninstalling else { return }
        isUninstalling = true

        let url = item.url
        let bundleID = item.bundleID
        let appID = item.id

        Task.detached(priority: .userInitiated) {
            if let bundleID {
                NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.terminate()
            }
            var failure: String?
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } catch {
                failure = error.localizedDescription
            }
            await MainActor.run {
                self.isUninstalling = false
                if let failure {
                    self.userAlert = UserAlert(title: "卸载失败", message: failure)
                    return
                }
                self.forget(appID)
                self.rescan()
            }
        }
    }

    private func forget(_ id: String) {
        order.removeAll { $0 == id }
        hidden.remove(id)
        usage[id] = nil
        for index in folders.indices {
            folders[index].appIDs.removeAll { $0 == id }
        }
        removeEmptyFolders()
        saveLayout()
        clampSelection()
    }

    private func removeEmptyFolders() {
        folders.removeAll { $0.appIDs.isEmpty }
        let liveFolders = Set(folders.map(\.id))
        order.removeAll { $0.hasPrefix("folder.") && !liveFolders.contains($0) }
        if let open = openFolderID, !liveFolders.contains(open) { openFolderID = nil }
    }

    private func presentAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Folders

    func createFolder(sourceID: String, targetID: String) {
        guard sourceID != targetID,
              appMap[sourceID] != nil,
              appMap[targetID] != nil else { return }
        let folder = AppFolder(id: "folder." + UUID().uuidString, name: "文件夹", appIDs: [targetID, sourceID])
        folders.append(folder)
        order.removeAll { $0 == sourceID }
        if let index = order.firstIndex(of: targetID) {
            order[index] = folder.id
        } else {
            order.append(folder.id)
        }
        settings.sortMode = .custom
        saveLayout()
    }

    func addToFolder(folderID: String, appID: String) {
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return }
        guard appMap[appID] != nil else { return }
        if !folders[index].appIDs.contains(appID) {
            folders[index].appIDs.append(appID)
        }
        order.removeAll { $0 == appID }
        saveLayout()
    }

    func removeFromFolder(folderID: String, appID: String) {
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[index].appIDs.removeAll { $0 == appID }
        if let position = order.firstIndex(of: folderID) {
            order.insert(appID, at: min(position + 1, order.count))
        } else {
            order.append(appID)
        }
        if folders[index].appIDs.count <= 1 {
            dissolveFolder(folderID)
        } else {
            saveLayout()
        }
    }

    func dissolveFolder(_ folderID: String) {
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return }
        let members = folders[index].appIDs
        let position = order.firstIndex(of: folderID) ?? order.count
        order.removeAll { $0 == folderID }
        order.insert(contentsOf: members, at: min(position, order.count))
        folders.remove(at: index)
        if openFolderID == folderID { openFolderID = nil }
        saveLayout()
    }

    func requestRenameFolder(_ folderID: String) {
        guard let folder = folders.first(where: { $0.id == folderID }) else { return }
        renamingText = folder.name
        renamingFolderID = folderID
    }

    func commitRenameFolder() {
        defer { renamingFolderID = nil }
        guard let id = renamingFolderID,
              let index = folders.firstIndex(where: { $0.id == id }) else { return }
        let name = renamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        folders[index].name = name
        saveLayout()
    }

    func cancelRenameFolder() {
        renamingFolderID = nil
    }

    // MARK: - Reordering

    func moveItem(_ sourceID: String, relativeTo targetID: String, after: Bool) {
        guard sourceID != targetID else { return }
        var ids = topLevelEntries.map(\.id)
        guard let from = ids.firstIndex(of: sourceID) else { return }
        let moved = ids.remove(at: from)
        guard let to = ids.firstIndex(of: targetID) else { return }
        ids.insert(moved, at: after ? to + 1 : to)
        order = ids
        settings.sortMode = .custom
        saveLayout()
    }

    func moveItemToEnd(_ sourceID: String) {
        guard let from = order.firstIndex(of: sourceID) else { return }
        let moved = order.remove(at: from)
        order.append(moved)
        settings.sortMode = .custom
        saveLayout()
    }

    // MARK: - Selection

    enum Move { case left, right, up, down }

    func move(_ direction: Move) {
        let count = visibleItems.count
        guard count > 0 else { return }
        let columns = max(1, settings.columns)
        var index = min(max(0, selection), count - 1)

        switch direction {
        case .left: index -= 1
        case .right: index += 1
        case .up: index -= columns
        case .down: index += columns
        }
        index = min(max(0, index), count - 1)
        selection = index
        page = index / perPage
    }

    func select(page target: Int) {
        let pages = self.pages
        guard !pages.isEmpty else { return }
        let clamped = min(max(0, target), pages.count - 1)
        guard clamped != page else { return }
        pageDirection = clamped > page ? 1 : -1
        page = clamped
        selection = min(page * perPage, max(0, visibleItems.count - 1))
    }

    func nextPage() { select(page: page + 1) }
    func previousPage() { select(page: page - 1) }

    func resetSelection() {
        selection = 0
        page = 0
    }

    private func clampSelection() {
        let count = visibleItems.count
        if count == 0 {
            selection = 0
            page = 0
            return
        }
        selection = min(max(0, selection), count - 1)
        page = min(max(0, page), max(0, pageCount - 1))
    }
}
