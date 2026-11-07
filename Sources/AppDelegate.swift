import AppKit
import SwiftUI

final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
                   styleMask: [.borderless, .fullSizeContentView],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        level = NSWindow.Level(rawValue: 90)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel.shared
    private var panel: LauncherPanel?
    private var statusItem: NSStatusItem?
    private var hotKey: HotKeyManager?
    private var settingsWindow: NSWindow?
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var cornerTimer: Timer?
    private var cornerArmed = true

    private let launchDate = Date()
    private var isHiding = false
    private var scrollX: CGFloat = 0
    private var scrollY: CGFloat = 0
    private var lastScroll = Date.distantPast
    private var scrollCooldown = Date.distantPast

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !model.panelVisible { show() }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard Date().timeIntervalSince(launchDate) > 2 else { return }
        guard !model.panelVisible else { return }
        guard NSApp.modalWindow == nil else { return }
        if let settingsWindow, settingsWindow.isVisible { return }
        show()
    }

    func applicationDidResignActive(_ notification: Notification) {
        guard model.panelVisible else { return }
        if let settingsWindow, settingsWindow.isVisible { return }
        if NSApp.modalWindow != nil { return }
        hide()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("overlay launcher keeps running")
        buildMainMenu()
        model.load()
        setupStatusItem()

        hotKey = HotKeyManager { [weak self] in self?.toggle() }
        registerHotKey()
        NotificationCenter.default.addObserver(self, selector: #selector(hotKeyChanged),
                                               name: .launchDeckHotKeyChanged, object: nil)

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(distributedToggle),
            name: NSNotification.Name("app.hermes.LaunchDeck.toggle"),
            object: nil
        )

        if ProcessInfo.processInfo.environment["LAUNCHDECK_DEBUG"] == "1" {
            let debugNames: [(String, Selector)] = [
                ("app.hermes.LaunchDeck.debug.query", #selector(debugQuery)),
                ("app.hermes.LaunchDeck.debug.key", #selector(debugKey)),
                ("app.hermes.LaunchDeck.debug.settings", #selector(debugSettings)),
                ("app.hermes.LaunchDeck.debug.folder", #selector(debugFolder)),
                ("app.hermes.LaunchDeck.debug.openfolder", #selector(debugOpenFolder)),
                ("app.hermes.LaunchDeck.debug.uninstall", #selector(debugUninstall)),
                ("app.hermes.LaunchDeck.debug.dissolve", #selector(debugDissolve)),
                ("app.hermes.LaunchDeck.debug.page", #selector(debugPage)),
                ("app.hermes.LaunchDeck.debug.corner", #selector(debugCorner)),
                ("app.hermes.LaunchDeck.debug.restart", #selector(debugRestart)),
                ("app.hermes.LaunchDeck.debug.uninstallui", #selector(debugUninstallUI)),
                ("app.hermes.LaunchDeck.debug.confirmuninstall", #selector(debugConfirmUninstall)),
                ("app.hermes.LaunchDeck.debug.effect", #selector(debugEffect)),
                ("app.hermes.LaunchDeck.debug.dump", #selector(debugDump)),
            ]
            for (name, selector) in debugNames {
                DistributedNotificationCenter.default().addObserver(
                    self, selector: selector, name: NSNotification.Name(name), object: nil)
            }
        }

        NotificationCenter.default.addObserver(self, selector: #selector(closeRequested),
                                               name: .launchDeckShouldClose, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(openSettingsRequested),
                                               name: .launchDeckOpenSettings, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(restartRequested),
                                               name: .launchDeckRestart, object: nil)

        cornerTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkHotCorner() }
        }

        if !UserDefaults.standard.bool(forKey: "launchdeck.seen") {
            UserDefaults.standard.set(true, forKey: "launchdeck.seen")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.show() }
        }
    }

    @objc private func closeRequested() {
        hide()
    }
    @objc private func distributedToggle() { toggle() }

    private func handleEscape() {
        if model.openFolderID != nil {
            model.closeFolder()
        } else if !model.query.isEmpty {
            model.query = ""
        } else {
            hide()
        }
    }

    // MARK: - Hotkey

    @objc private func hotKeyChanged() {
        registerHotKey()
    }

    @objc private func openSettingsRequested() { menuSettings() }

    @objc private func restartRequested() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", Bundle.main.bundlePath]
        try? task.run()
        task.waitUntilExit()
        NSApp.terminate(nil)
    }

    private func registerHotKey() {
        hotKey?.register(keyCode: Shortcut.keyCode, modifiers: Shortcut.modifiers)
    }

    // MARK: - Debug hooks

    @objc private func debugQuery(_ note: Notification) {
        guard let query = note.userInfo?["q"] as? String else { return }
        model.query = query
    }

    @objc private func debugSettings() { menuSettings() }
    @objc private func debugRestart() { restartRequested() }

    @objc private func debugPage(_ note: Notification) {
        let delta = (note.userInfo?["delta"] as? String).flatMap(Int.init) ?? 1
        model.select(page: model.page + delta)
    }

    @objc private func debugCorner(_ note: Notification) {
        let x = (note.userInfo?["x"] as? String).flatMap(Double.init) ?? 2
        let y = (note.userInfo?["y"] as? String).flatMap(Double.init) ?? 2
        checkHotCorner(at: CGPoint(x: x, y: y))
    }

    @objc private func debugFolder(_ note: Notification) {
        guard let source = note.userInfo?["source"] as? String,
              let target = note.userInfo?["target"] as? String else { return }
        model.createFolder(sourceID: source, targetID: target)
    }

    @objc private func debugOpenFolder(_ note: Notification) {
        guard let id = note.userInfo?["id"] as? String else { return }
        model.openFolderID = id
    }

    @objc private func debugUninstall(_ note: Notification) {
        guard let id = note.userInfo?["id"] as? String,
              let app = model.apps.first(where: { $0.id == id }) else { return }
        model.uninstall(app, confirm: false)
    }

    @objc private func debugUninstallUI(_ note: Notification) {
        guard let id = note.userInfo?["id"] as? String,
              let app = model.apps.first(where: { $0.id == id }) else { return }
        model.uninstall(app)
    }

    @objc private func debugConfirmUninstall() {
        model.confirmUninstall()
    }

    @objc private func debugDissolve(_ note: Notification) {
        guard let id = note.userInfo?["id"] as? String else { return }
        model.dissolveFolder(id)
    }

    @objc private func debugEffect(_ note: Notification) {
        guard let name = note.userInfo?["name"] as? String,
              let effect = PageEffect(rawValue: name) else { return }
        model.settings.pageEffect = effect
    }

    @objc private func debugDump() {
        let state: [String: Any] = [
            "page": model.page,
            "pageCount": model.pageCount,
            "effect": model.settings.pageEffect.rawValue,
            "items": model.visibleItems.count,
            "selection": model.selection,
            "folders": model.folders.count,
            "panelVisible": model.panelVisible,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted]) {
            try? data.write(to: URL(fileURLWithPath: "/tmp/launchdeck-state.json"))
        }
    }

    @objc private func debugKey(_ note: Notification) {
        switch note.userInfo?["key"] as? String {
        case "up": model.move(.up)
        case "down": model.move(.down)
        case "left": model.move(.left)
        case "right": model.move(.right)
        case "enter": model.activateSelected()
        case "escape": handleEscape()
        default: break
        }
    }

    // MARK: - Panel

    private func ensurePanel() -> LauncherPanel {
        if let panel { return panel }
        let created = LauncherPanel()
        panel = created
        return created
    }

    private func targetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    func toggle() {
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard let screen = targetScreen() else { return }
        installMonitors()

        model.query = ""
        model.closeFolder()
        model.resetSelection()
        model.rescan()

        let wallpaper = Wallpaper.image(for: screen, blurred: model.settings.blurWallpaper)
        let root = AnyView(
            LauncherRootView(model: model, wallpaper: wallpaper)
                .frame(width: screen.frame.width, height: screen.frame.height)
        )
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: screen.frame.size)

        let panel = ensurePanel()
        panel.setFrame(screen.frame, display: true)
        panel.contentView = host
        panel.alphaValue = 1
        model.panelVisible = false
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if model.settings.hideDock {
            NSApp.presentationOptions = [.autoHideDock, .autoHideMenuBar]
        }

        // One run loop later so SwiftUI animates the zoom-in instead of starting at the end state.
        DispatchQueue.main.async { [weak self] in
            self?.model.panelVisible = true
            NotificationCenter.default.post(name: .launchDeckFocusSearch, object: nil)
        }
    }

    func hide() {
        guard let panel, panel.isVisible, !isHiding else { return }
        isHiding = true

        model.panelVisible = false
        NSApp.presentationOptions = []

        // Let the SwiftUI scale/fade finish before the panel leaves the screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            panel.orderOut(nil)
            self?.isHiding = false
            NSApp.hide(nil)
        }
    }

    private func installMonitors() {
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let panel = self.panel, panel.isVisible else { return event }
                if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() {
                    return event
                }
                if event.keyCode == 53 {
                    self.handleEscape()
                    return nil
                }
                if event.keyCode == 36 || event.keyCode == 76 {
                    self.model.activateSelected()
                    return nil
                }
                return event
            }
        }
        if scrollMonitor == nil {
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let panel = self.panel, panel.isVisible else { return event }
                self.handleScroll(event)
                return nil
            }
        }
    }

    private func handleScroll(_ event: NSEvent) {
        let now = Date()
        if now.timeIntervalSince(lastScroll) > 0.4 {
            scrollX = 0
            scrollY = 0
        }
        lastScroll = now
        guard now >= scrollCooldown else { return }

        scrollX += event.scrollingDeltaX
        scrollY += event.scrollingDeltaY

        let precise = event.hasPreciseScrollingDeltas
        let threshold: CGFloat = precise ? 60 : 4

        if abs(scrollX) > abs(scrollY), abs(scrollX) > threshold {
            model.select(page: model.page + (scrollX < 0 ? 1 : -1))
            scrollX = 0
            scrollY = 0
            scrollCooldown = now.addingTimeInterval(0.22)
        } else if abs(scrollY) > threshold {
            model.select(page: model.page + (scrollY < 0 ? 1 : -1))
            scrollX = 0
            scrollY = 0
            scrollCooldown = now.addingTimeInterval(0.22)
        }
    }

    // MARK: - Hot corner

    private func checkHotCorner() {
        checkHotCorner(at: NSEvent.mouseLocation)
    }

    private func checkHotCorner(at mouse: CGPoint) {
        let corner = model.settings.hotCorner
        guard corner != .off else { return }
        if let panel, panel.isVisible { return }

        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) else { return }
        let frame = screen.frame
        let inset: CGFloat = 4

        let inside: Bool
        switch corner {
        case .off:
            return
        case .topLeft:
            inside = mouse.x - frame.minX < inset && frame.maxY - mouse.y < inset
        case .topRight:
            inside = frame.maxX - mouse.x < inset && frame.maxY - mouse.y < inset
        case .bottomLeft:
            inside = mouse.x - frame.minX < inset && mouse.y - frame.minY < inset
        case .bottomRight:
            inside = frame.maxX - mouse.x < inset && mouse.y - frame.minY < inset
        }

        if inside, cornerArmed {
            cornerArmed = false
            NSLog("LaunchDeck: hot corner triggered at %@", NSStringFromPoint(mouse))
            show()
        } else if !inside {
            cornerArmed = true
        }
    }

    // MARK: - Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "LaunchDeck")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(statusButtonClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    @objc private func statusButtonClicked() {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            statusItem?.menu = makeStatusMenu()
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else {
            toggle()
        }
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "打开 LaunchDeck", action: #selector(menuOpen), keyEquivalent: "").target = self
        menu.addItem(withTitle: "设置…", action: #selector(menuSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "重新扫描应用", action: #selector(menuRescan), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 LaunchDeck", action: #selector(menuQuit), keyEquivalent: "q").target = self
        return menu
    }

    @objc private func menuOpen() { show() }
    @objc private func menuRescan() { model.rescan() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    @objc private func menuSettings() {
        // The settings window is a normal window; the full-screen panel would cover it.
        if let panel, panel.isVisible {
            model.panelVisible = false
            panel.orderOut(nil)
        }
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "LaunchDeck 设置"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    // MARK: - Menu bar

    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于 LaunchDeck",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "设置…", action: #selector(menuSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 LaunchDeck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "编辑")
        editItem.submenu = edit
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = main
    }
}
