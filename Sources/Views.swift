import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Search field

enum SearchCommand {
    case up, down, enter, escape
}

final class KeyTextField: NSTextField {
    var onCommand: ((SearchCommand) -> Void)?
}

struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var focusTick: Int
    var onCommand: (SearchCommand) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> KeyTextField {
        let field = KeyTextField()
        field.delegate = context.coordinator
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 17)
        field.textColor = .white
        field.usesSingleLineMode = true
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.onCommand = onCommand
        field.placeholderAttributedString = NSAttributedString(
            string: "搜索应用",
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.45),
                .font: NSFont.systemFont(ofSize: 17),
            ]
        )
        context.coordinator.field = field
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ field: KeyTextField, context: Context) {
        context.coordinator.parent = self
        field.onCommand = onCommand
        if field.stringValue != text {
            field.stringValue = text
        }
        if context.coordinator.lastFocusTick != focusTick {
            context.coordinator.lastFocusTick = focusTick
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchField
        weak var field: NSTextField?
        var lastFocusTick = -1

        init(_ parent: SearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onCommand(.up)
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onCommand(.down)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onCommand(.enter)
                return true
            default:
                return false
            }
        }
    }
}

// MARK: - Root overlay

struct LauncherRootView: View {
    @ObservedObject var model: AppModel
    let wallpaper: NSImage?

    @State private var focusTick = 0
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                searchBar
                    .padding(.top, 54)

                grid
                    .padding(.top, 30)
                    .padding(.horizontal, 92)

                PageDots(model: model)
                    .padding(.top, 22)
                    .padding(.bottom, 36)
            }

            if let folder = model.openFolder {
                FolderOverlay(model: model, folder: folder)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .zIndex(2)
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.openFolderID)
        .contextMenu { backgroundMenu }
        .scaleEffect(model.panelVisible ? 1 : 0.9)
        .opacity(model.panelVisible ? 1 : 0)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: model.panelVisible)
        .onAppear { focusTick += 1 }
        .onReceive(NotificationCenter.default.publisher(for: .launchDeckFocusSearch)) { _ in
            focusTick += 1
        }
    }

    private var background: some View {
        ZStack {
            if let wallpaper, model.settings.blurWallpaper {
                Image(nsImage: wallpaper)
                    .resizable()
                    .scaledToFill()
                    .overlay(Color.black.opacity(model.settings.dim))
                    .ignoresSafeArea()
            } else {
                LinearGradient(colors: [Color(red: 0.07, green: 0.09, blue: 0.14),
                                        Color(red: 0.02, green: 0.03, blue: 0.06)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }
            if model.settings.blurWallpaper {
                VisualEffect(material: .fullScreenUI, blending: .behindWindow)
                    .ignoresSafeArea()
                    .opacity(0.55)
            }
        }
        .contextMenu { backgroundMenu }
    }

    @ViewBuilder
    private var backgroundMenu: some View {
        Button("重新启动 LaunchDeck") {
            NotificationCenter.default.post(name: .launchDeckRestart, object: nil)
        }
        Button("设置…") {
            NotificationCenter.default.post(name: .launchDeckOpenSettings, object: nil)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            SearchField(text: $model.query, focusTick: focusTick, onCommand: handle)
                .frame(height: 24)
        }
        .padding(.horizontal, 18)
        .frame(width: 460, height: 48)
        .background(Capsule().fill(.white.opacity(0.13)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
    }

    @ViewBuilder
    private var grid: some View {
        GeometryReader { geo in
            let columns = max(1, model.settings.columns)
            let rows = max(1, model.settings.rows)
            let labelHeight = model.settings.showLabels ? 28.0 : 0.0
            let rowHeight = geo.size.height / Double(rows)

            // Fit the icon to the row, then let the leftover become the gap. The icon is capped by
            // the column width so a wide grid still fits, and the block is centred by the parent.
            let gap0 = rowHeight * model.settings.gapRatio
            let maxByWidth = geo.size.width / Double(columns) - gap0
            let baseIcon = min(max(44, rowHeight - labelHeight - gap0), max(40, maxByWidth))
            let iconSize = max(28, baseIcon * model.settings.iconScale)
            let gap = max(8, rowHeight - labelHeight - iconSize)

            let pad = min(18.0, gap * 0.4)
            let cellWidth = iconSize + pad * 2
            let cellHeight = iconSize + labelHeight + pad * 2
            let columnSpacing = max(0, gap - pad * 2)
            let rowSpacing = max(0, gap - pad * 2)

            let items = model.currentPageItems

            if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: model.isSearching ? "magnifyingglass" : "square.grid.3x3")
                        .font(.system(size: 38, weight: .light))
                    Text(model.isSearching ? "没有找到匹配的应用" : "没有找到应用")
                        .font(.system(size: 16))
                }
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack {
                    // Press-and-drag on empty space flips pages; the grid follows the pointer.
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 20)
                                .onChanged { value in
                                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                                    dragOffset = value.translation.width * 0.35
                                }
                                .onEnded { value in
                                    let dx = value.translation.width
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                                        dragOffset = 0
                                    }
                                    guard abs(dx) > abs(value.translation.height), abs(dx) > 110 else { return }
                                    if dx < 0 {
                                        model.select(page: model.page + 1)
                                    } else {
                                        model.select(page: model.page - 1)
                                    }
                                }
                        )

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(cellWidth), spacing: columnSpacing), count: columns),
                        spacing: rowSpacing
                    ) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, entry in
                            let globalIndex = model.page * model.perPage + index
                            cell(for: entry, index: globalIndex, iconSize: iconSize, cellWidth: cellWidth)
                                .frame(width: cellWidth, height: cellHeight)
                                .modifier(AppearOnPage(delay: Double(index) * 0.012))
                        }
                    }
                    .offset(x: dragOffset)
                    .id(model.page)
                    .transition(pageTransition)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .animation(.spring(response: 0.4, dampingFraction: 0.9), value: model.page)
            }
        }
    }

    @ViewBuilder
    private func cell(for entry: LauncherEntry, index: Int, iconSize: Double, cellWidth: Double) -> some View {
        switch entry {
        case .app(let item):
            AppCell(
                item: item,
                icon: model.icon(for: item.id),
                isSelected: model.selection == index,
                iconSize: iconSize,
                showLabel: model.settings.showLabels,
                isRunning: model.isRunning(item),
                isSystem: model.isSystemApp(item),
                isLaunching: model.launchingID == item.id,
                draggable: model.settings.sortMode == .custom && !model.isSearching,
                onOpen: {
                    model.selection = index
                    model.launch(item)
                },
                onReveal: { model.reveal(item) },
                onUninstall: { model.uninstall(item) },
                onHide: { model.hideFromLauncher(item) },
                onHideApp: { model.hideRunningApp(item) },
                onQuit: { model.quitRunningApp(item) },
                onDrop: { payload, location in
                    let centered = abs(location.x - cellWidth / 2) < cellWidth * 0.24
                    if centered, !payload.hasPrefix("folder."), payload != item.id {
                        model.createFolder(sourceID: payload, targetID: item.id)
                    } else {
                        model.moveItem(payload, relativeTo: item.id, after: location.x > cellWidth / 2)
                    }
                    return true
                }
            )

        case .folder(let folder):
            FolderCell(
                folder: folder,
                previews: model.folderPreviewIcons(folder),
                isSelected: model.selection == index,
                iconSize: iconSize,
                showLabel: model.settings.showLabels,
                onOpen: {
                    model.selection = index
                    model.openFolderID = folder.id
                },
                onRename: { model.renameFolder(folder.id) },
                onDissolve: { model.dissolveFolder(folder.id) },
                onDrop: { payload in
                    guard !payload.hasPrefix("folder.") else { return false }
                    model.addToFolder(folderID: folder.id, appID: payload)
                    return true
                }
            )
        }
    }

    private var pageTransition: AnyTransition {
        let forward = model.pageDirection >= 0
        return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private func handle(_ command: SearchCommand) {
        switch command {
        case .up: model.move(.up)
        case .down: model.move(.down)
        case .enter: model.activateSelected()
        case .escape:
            NotificationCenter.default.post(name: .launchDeckShouldClose, object: nil)
        }
    }
}

// MARK: - Cells

struct AppCell: View {
    let item: AppItem
    let icon: NSImage?
    let isSelected: Bool
    let iconSize: Double
    let showLabel: Bool
    let isRunning: Bool
    let isSystem: Bool
    let isLaunching: Bool
    let draggable: Bool
    let onOpen: () -> Void
    let onReveal: () -> Void
    let onUninstall: () -> Void
    let onHide: () -> Void
    let onHideApp: () -> Void
    let onQuit: () -> Void
    var onMoveOut: (() -> Void)? = nil
    var onDrop: ((String, CGPoint) -> Bool)? = nil

    @State private var hovering = false
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                Group {
                    if let icon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                    } else {
                        RoundedRectangle(cornerRadius: iconSize * 0.23)
                            .fill(Color.white.opacity(0.15))
                            .overlay(
                                Image(systemName: "app.dashed")
                                    .font(.system(size: iconSize * 0.35))
                                    .foregroundStyle(.white.opacity(0.5))
                            )
                    }
                }
                .frame(width: iconSize, height: iconSize)
                .shadow(color: .black.opacity(hovering ? 0.5 : 0.32), radius: hovering ? 18 : 12, y: 7)
                .scaleEffect(hovering ? 1.05 : 1)

                if isRunning {
                    Circle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 5, height: 5)
                        .offset(y: iconSize + 5)
                }
            }

            if showLabel {
                Text(item.name)
                    .font(.system(size: max(12, min(17, iconSize * 0.085)), weight: .medium))
                    .foregroundStyle(.white.opacity(hovering || isSelected ? 1 : 0.9))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(hovering || isSelected ? 0.4 : 0)))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(isSelected ? 0.14 : (hovering ? 0.07 : 0)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.white.opacity(targeted ? 0.65 : (isSelected ? 0.3 : 0)), lineWidth: targeted ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onOpen)
        .contextMenu {
            Button("打开", action: onOpen)
            Button("在 Finder 中显示", action: onReveal)
            Divider()
            if let onMoveOut {
                Button("移出文件夹", action: onMoveOut)
            }
            if isRunning {
                Button("隐藏", action: onHideApp)
                Button("退出", action: onQuit)
                Divider()
            }
            Button("从启动器中隐藏", action: onHide)
            if !isSystem {
                Button("卸载…", action: onUninstall)
            }
        }
        .modifier(AppDragModifier(enabled: draggable, id: item.id, onDrop: onDrop, targeted: $targeted))
        .scaleEffect(isLaunching ? 1.5 : 1)
        .opacity(isLaunching ? 0 : 1)
        .animation(.easeIn(duration: 0.18), value: isLaunching)
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

struct AppearOnPage: ViewModifier {
    let delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.88)
            .onAppear {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.8).delay(min(delay, 0.2))) {
                    shown = true
                }
            }
    }
}

private struct AppDragModifier: ViewModifier {
    let enabled: Bool
    let id: String
    let onDrop: ((String, CGPoint) -> Bool)?
    @Binding var targeted: Bool

    func body(content: Content) -> some View {
        if enabled, let onDrop {
            content
                .draggable(id)
                .dropDestination(for: String.self, action: { payloads, location in
                    guard let source = payloads.first else { return false }
                    return onDrop(source, location)
                }, isTargeted: { targeted = $0 })
        } else {
            content
        }
    }
}

struct FolderCell: View {
    let folder: AppFolder
    let previews: [NSImage?]
    let isSelected: Bool
    let iconSize: Double
    let showLabel: Bool
    let onOpen: () -> Void
    let onRename: () -> Void
    let onDissolve: () -> Void
    let onDrop: (String) -> Bool

    @State private var hovering = false
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: iconSize * 0.23)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: iconSize * 0.23)
                            .fill(Color.white.opacity(0.08))
                    )

                LazyVGrid(columns: [
                    GridItem(.fixed(iconSize * 0.36), spacing: iconSize * 0.05),
                    GridItem(.fixed(iconSize * 0.36), spacing: iconSize * 0.05),
                ], spacing: iconSize * 0.05) {
                    ForEach(0 ..< 4, id: \.self) { index in
                        Group {
                            if index < previews.count, let image = previews[index] {
                                Image(nsImage: image)
                                    .resizable()
                                    .interpolation(.high)
                                    .aspectRatio(contentMode: .fit)
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: iconSize * 0.36, height: iconSize * 0.36)
                    }
                }
            }
            .frame(width: iconSize, height: iconSize)
            .shadow(color: .black.opacity(hovering ? 0.5 : 0.32), radius: hovering ? 18 : 12, y: 7)
            .scaleEffect(hovering ? 1.05 : 1)

            if showLabel {
                Text(folder.name)
                    .font(.system(size: max(12, min(17, iconSize * 0.085)), weight: .medium))
                    .foregroundStyle(.white.opacity(hovering || isSelected ? 1 : 0.9))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(hovering || isSelected ? 0.4 : 0)))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(isSelected ? 0.14 : (hovering ? 0.07 : 0)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.white.opacity(targeted ? 0.65 : (isSelected ? 0.3 : 0)), lineWidth: targeted ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onOpen)
        .contextMenu {
            Button("打开", action: onOpen)
            Button("重命名…", action: onRename)
            Divider()
            Button("解散文件夹", action: onDissolve)
        }
        .dropDestination(for: String.self, action: { payloads, _ in
            guard let source = payloads.first else { return false }
            return onDrop(source)
        }, isTargeted: { targeted = $0 })
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

// MARK: - Folder overlay

struct FolderOverlay: View {
    @ObservedObject var model: AppModel
    let folder: AppFolder

    private let columns = 4

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { model.closeFolder() }

            VStack(spacing: 22) {
                HStack {
                    Text(folder.name)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        model.closeFolder()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                }

                Spacer(minLength: 10)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: columns),
                          spacing: 18) {
                    ForEach(model.folderApps(folder), id: \.id) { app in
                        AppCell(
                            item: app,
                            icon: model.icon(for: app.id),
                            isSelected: false,
                            iconSize: 96,
                            showLabel: true,
                            isRunning: model.isRunning(app),
                            isSystem: model.isSystemApp(app),
                            isLaunching: false,
                            draggable: false,
                            onOpen: { model.launch(app) },
                            onReveal: { model.reveal(app) },
                            onUninstall: { model.uninstall(app) },
                            onHide: { model.hideFromLauncher(app) },
                            onHideApp: { model.hideRunningApp(app) },
                            onQuit: { model.quitRunningApp(app) },
                            onMoveOut: { model.removeFromFolder(folderID: folder.id, appID: app.id) }
                        )
                    }
                }

                Spacer(minLength: 10)
            }
            .padding(34)
            .frame(width: 760)
            .frame(minHeight: 320)
            .background(
                RoundedRectangle(cornerRadius: 36)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 36)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 40, y: 22)
        }
    }
}

// MARK: - Page dots

struct PageDots: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            if model.pageCount > 1 {
                ForEach(0 ..< model.pageCount, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(index == model.page ? 0.95 : 0.32))
                        .frame(width: index == model.page ? 8 : 6, height: index == model.page ? 8 : 6)
                        .contentShape(Rectangle().inset(by: -6))
                        .onTapGesture { model.select(page: index) }
                }
            } else {
                Text(model.isSearching
                     ? "\(model.visibleItems.count) 个结果"
                     : "\(model.visibleItems.count) 项")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(height: 12)
        .animation(.easeOut(duration: 0.18), value: model.page)
    }
}

struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blending: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var recording = false
    @State private var recorder: Any?

    var body: some View {
        Form {
            Section("网格") {
                Stepper("横排：\(model.settings.columns) 格", value: $model.settings.columns, in: 4 ... 12)
                Stepper("竖排：\(model.settings.rows) 格", value: $model.settings.rows, in: 2 ... 8)
                HStack {
                    Text("间距")
                    Slider(value: $model.settings.gapRatio, in: 0.08 ... 0.34, step: 0.01)
                    Text("\(Int(model.settings.gapRatio * 100))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 46, alignment: .trailing)
                    Button("自动") { model.settings.gapRatio = 0.18 }
                        .buttonStyle(.link)
                }
                HStack {
                    Text("图标大小")
                    Slider(value: $model.settings.iconScale, in: 0.55 ... 1.1, step: 0.01)
                    Text("\(Int(model.settings.iconScale * 100))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 46, alignment: .trailing)
                    Button("自动") { model.settings.iconScale = 0.85 }
                        .buttonStyle(.link)
                }
                Toggle("显示应用名称", isOn: $model.settings.showLabels)
                Text("图标先按格数推导，再乘以这里的百分比；整块网格始终居中，四边留白一致。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("交互") {
                Picker("热角呼出", selection: $model.settings.hotCorner) {
                    ForEach(HotCorner.allCases, id: \.self) { corner in
                        Text(corner.label).tag(corner)
                    }
                }
                HStack {
                    Text("呼出快捷键")
                    Spacer()
                    Text(Shortcut.label)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Button(recording ? "请按下…" : "录制") { toggleRecording() }
                    Button("还原") { Shortcut.reset() }
                }
                Toggle("打开时隐藏 Dock 和菜单栏", isOn: $model.settings.hideDock)
                Text("触控板左右轻扫、滚轮上下滚动、在空白处按住拖动都可以翻页。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("外观") {
                Toggle("模糊桌面壁纸", isOn: $model.settings.blurWallpaper)
                Toggle("在搜索中包含已隐藏应用", isOn: $model.settings.showHiddenInSearch)
                HStack {
                    Text("壁纸暗度")
                    Slider(value: $model.settings.dim, in: 0 ... 0.7, step: 0.02)
                    Text("\(Int(model.settings.dim * 100))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 46, alignment: .trailing)
                }
            }

            Section("排序") {
                Picker("排序方式", selection: $model.settings.sortMode) {
                    ForEach(SortMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Button("重置为名称顺序") { model.settings.sortMode = .name }
            }

            Section("应用与数据") {
                Button("重新扫描应用") { model.rescan() }
                Button("恢复已隐藏的 \(model.hidden.count) 个应用") { model.unhideAll() }
                    .disabled(model.hidden.isEmpty)
                HStack {
                    Button("导出布局…") { exportLayout() }
                    Button("导入布局…") { importLayout() }
                }
                Toggle("登录时启动", isOn: Binding(
                    get: { model.settings.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                Text("布局包含顺序、文件夹、隐藏列表与使用次数。拖到图标中央建文件夹，拖到左右边缘调整位置。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("关于") {
                LabeledContent("版本", value: "1.5 (6)")
                LabeledContent("呼出快捷键", value: Shortcut.label)
                Text("LaunchDeck 是一个自建的启动器：读取 /Applications、/System/Applications 与 ~/Applications，支持文件夹、拖拽排序、右键卸载、热角与自定义快捷键。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 760)
    }

    private func toggleRecording() {
        if recording {
            if let recorder { NSEvent.removeMonitor(recorder) }
            self.recorder = nil
            recording = false
            return
        }
        recording = true
        recorder = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc cancels recording
                recording = false
                if let recorder { NSEvent.removeMonitor(recorder) }
                self.recorder = nil
                return nil
            }
            let modifiers = Shortcut.carbonModifiers(from: event.modifierFlags)
            guard modifiers != 0 else { return nil }
            let label = Shortcut.describe(keyCode: event.keyCode,
                                          characters: event.charactersIgnoringModifiers,
                                          flags: event.modifierFlags)
            Shortcut.save(keyCode: UInt32(event.keyCode), modifiers: modifiers, label: label)
            recording = false
            if let recorder { NSEvent.removeMonitor(recorder) }
            self.recorder = nil
            return nil
        }
    }

    private func exportLayout() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "LaunchDeck-layout.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !model.exportLayout(to: url) {
            let alert = NSAlert()
            alert.messageText = "导出失败"
            alert.informativeText = "无法写入 \(url.path)"
            alert.runModal()
        }
    }

    private func importLayout() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !model.importLayout(from: url) {
            let alert = NSAlert()
            alert.messageText = "导入失败"
            alert.informativeText = "这个文件不是有效的 LaunchDeck 布局。"
            alert.runModal()
        }
    }
}
