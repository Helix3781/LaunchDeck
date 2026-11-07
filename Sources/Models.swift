import AppKit
import Foundation

/// One launchable application discovered on disk.
struct AppItem: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let bundleID: String?
    let modified: Date

    static func == (lhs: AppItem, rhs: AppItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A folder made by dropping one icon onto another, Launchpad style.
struct AppFolder: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var appIDs: [String]
}

/// A slot on the launcher grid: a single app or a folder.
enum LauncherEntry: Identifiable {
    case app(AppItem)
    case folder(AppFolder)

    var id: String {
        switch self {
        case .app(let item): return item.id
        case .folder(let folder): return folder.id
        }
    }

    var appItem: AppItem? {
        if case .app(let item) = self { return item }
        return nil
    }

    var folderValue: AppFolder? {
        if case .folder(let folder) = self { return folder }
        return nil
    }
}

enum SortMode: String, CaseIterable, Codable {
    case custom
    case name
    case mostUsed
    case newest

    var label: String {
        switch self {
        case .custom: return "自定义顺序"
        case .name: return "名称"
        case .mostUsed: return "使用频率"
        case .newest: return "最近安装"
        }
    }
}

enum PageEffect: String, CaseIterable, Codable {
    case slide
    case smooth
    case fade
    case zoom
    case flip
    case none

    var label: String {
        switch self {
        case .slide: return "滑动 + 淡入（当前）"
        case .smooth: return "丝滑平移"
        case .fade: return "淡入淡出"
        case .zoom: return "缩放"
        case .flip: return "3D 翻转"
        case .none: return "无特效"
        }
    }
}

enum HotCorner: String, CaseIterable, Codable {
    case off
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var label: String {
        switch self {
        case .off: return "关闭"
        case .topLeft: return "左上角"
        case .topRight: return "右上角"
        case .bottomLeft: return "左下角"
        case .bottomRight: return "右下角"
        }
    }
}

struct UserAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct Usage: Codable {
    var count: Int = 0
    var last: Date = .distantPast
}

/// User-facing preferences, persisted in UserDefaults.
/// Version 3: the grid is described by columns, rows and a gap ratio; the icon size is derived so the
/// block fills the panel with equal margins instead of a hand-tuned point size.
struct Settings: Codable {
    var version: Int = 6
    var columns: Int = 8
    var rows: Int = 4
    var gapRatio: Double = 0.22
    var iconScale: Double = 0.85
    var showLabels: Bool = true
    var sortMode: SortMode = .custom
    var blurWallpaper: Bool = true
    var dim: Double = 0.28
    var showHiddenInSearch: Bool = false
    var pageEffect: PageEffect = .slide
    var hotCorner: HotCorner = .off
    var hideDock: Bool = false
    var launchAtLogin: Bool = false

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = 6
        columns = try container.decodeIfPresent(Int.self, forKey: .columns) ?? 8
        rows = try container.decodeIfPresent(Int.self, forKey: .rows) ?? 4
        gapRatio = try container.decodeIfPresent(Double.self, forKey: .gapRatio) ?? 0.22
        iconScale = try container.decodeIfPresent(Double.self, forKey: .iconScale) ?? 0.85
        showLabels = try container.decodeIfPresent(Bool.self, forKey: .showLabels) ?? true
        sortMode = try container.decodeIfPresent(SortMode.self, forKey: .sortMode) ?? .custom
        blurWallpaper = try container.decodeIfPresent(Bool.self, forKey: .blurWallpaper) ?? true
        dim = try container.decodeIfPresent(Double.self, forKey: .dim) ?? 0.28
        showHiddenInSearch = try container.decodeIfPresent(Bool.self, forKey: .showHiddenInSearch) ?? false
        pageEffect = try container.decodeIfPresent(PageEffect.self, forKey: .pageEffect) ?? .slide
        hotCorner = try container.decodeIfPresent(HotCorner.self, forKey: .hotCorner) ?? .off
        hideDock = try container.decodeIfPresent(Bool.self, forKey: .hideDock) ?? false
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false

        // Older builds shipped 7 x 5 / 88 pt, then 6 x 4 / 124 pt grids. Both are replaced once by the
        // adaptive layout; every other preference is kept.
        let storedVersion = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        if storedVersion < 3 {
            columns = 8
            rows = 4
        }
        if storedVersion < 4 {
            iconScale = 0.85
        }
        if storedVersion < 5 {
            gapRatio = 0.22
        }
        if storedVersion < 6 {
            pageEffect = .slide
        }
    }
}

struct LayoutFile: Codable {
    var order: [String] = []
    var hidden: [String] = []
    var usage: [String: Usage] = [:]
    var folders: [AppFolder] = []

    init() {}

    init(order: [String], hidden: [String], usage: [String: Usage], folders: [AppFolder]) {
        self.order = order
        self.hidden = hidden
        self.usage = usage
        self.folders = folders
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        order = try container.decodeIfPresent([String].self, forKey: .order) ?? []
        hidden = try container.decodeIfPresent([String].self, forKey: .hidden) ?? []
        usage = try container.decodeIfPresent([String: Usage].self, forKey: .usage) ?? [:]
        folders = try container.decodeIfPresent([AppFolder].self, forKey: .folders) ?? []
    }
}
