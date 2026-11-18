import AppKit
import CoreGraphics

/// Screen-region screenshot: a full-screen crosshair overlay, drag (or click twice) to pick a
/// rectangle, then the crop lands on the general pasteboard.
@MainActor
final class ScreenshotPicker {
    enum Outcome {
        case copied(size: CGSize)
        case cancelled
        case failed(String)
    }

    private var window: ScreenshotWindow?
    private var screen: NSScreen?
    private var completion: ((Outcome) -> Void)?

    // MARK: Permission

    /// Screen capture is gated by TCC: the first call raises the system prompt, later calls just
    /// report the current state. A false answer means the shot would come back empty.
    static var hasPermission: Bool {
        CGRequestScreenCaptureAccess()
    }

    static func explainPermission() {
        let alert = NSAlert()
        alert.messageText = "截图需要屏幕录制权限"
        alert.informativeText = """
        请在「系统设置 → 隐私与安全性 → 屏幕录制」里勾选 LaunchDeck，然后重新启动 LaunchDeck 让权限生效。
        授权之前截图只会得到空白图片。
        """
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenRecording")!
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Flow

    func begin(autoRect: NSRect? = nil, completion: @escaping (Outcome) -> Void) {
        guard self.window == nil else { return }

        let mouse = NSEvent.mouseLocation
        guard let target = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else {
            completion(.failed("找不到可用的显示器"))
            return
        }

        self.screen = target
        self.completion = completion

        // Debug/automation path: hand a rectangle straight to the capture step.
        if let autoRect {
            finish(autoRect)
            return
        }

        let window = ScreenshotWindow(frame: target.frame)
        let canvas = ScreenshotCanvasView(frame: NSRect(origin: .zero, size: target.frame.size))
        canvas.onFinish = { [weak self] rect in self?.finish(rect) }
        canvas.onCancel = { [weak self] in self?.cancel() }
        window.contentView = canvas
        window.setFrame(target.frame, display: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
        canvas.primeCursor(at: window.convertPoint(fromScreen: mouse))
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(_ rect: NSRect) {
        guard let screen, let completion = self.completion else { return }
        // Hide the overlay before grabbing, otherwise the dimming layer and the selection frame
        // end up baked into the shot.
        window?.orderOut(nil)
        window = nil
        self.completion = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            if let image = ScreenshotCapture.image(for: rect, on: screen), ScreenshotCapture.copy(image) {
                NSSound(named: "Tink")?.play()
                completion(.copied(size: image.size))
            } else {
                completion(.failed("截取失败：请检查「屏幕录制」权限后重启 LaunchDeck"))
            }
        }
    }

    private func cancel() {
        window?.orderOut(nil)
        window = nil
        let completion = self.completion
        self.completion = nil
        completion?(.cancelled)
    }
}

// MARK: - Window

private final class ScreenshotWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(frame: NSRect) {
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
        acceptsMouseMovedEvents = true
    }
}

// MARK: - Canvas

private final class ScreenshotCanvasView: NSView {
    var onFinish: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    /// First corner of the pending selection: kept after a plain click so a second click can
    /// finish the rectangle without dragging.
    private var anchor: NSPoint?
    private var cursorPoint: NSPoint?
    private var dragStart: NSPoint?
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    /// Seed the crosshair with the pointer position so the overlay reads correctly before the
    /// first mouse move.
    func primeCursor(at point: NSPoint) {
        cursorPoint = point
        needsDisplay = true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: Events

    override func mouseMoved(with event: NSEvent) {
        cursorPoint = convert(event.locationInWindow, from: nil)
        if anchor != nil { needsDisplay = true }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point

        if let anchor {
            // Second click of a click-click selection: finish right away.
            let rect = normalised(anchor, point)
            if rect.width >= 3, rect.height >= 3 {
                onFinish?(rect)
                return
            }
        }
        anchor = point
        cursorPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        cursorPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        cursorPoint = point
        guard let start = dragStart, let anchor else { return }
        if hypot(point.x - start.x, point.y - start.y) >= 4 {
            let rect = normalised(anchor, point)
            if rect.width >= 3, rect.height >= 3 {
                onFinish?(rect)
                return
            }
        }
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            onCancel?()
        case 36, 76: // Return / Enter
            if let anchor, let cursorPoint {
                let rect = normalised(anchor, cursorPoint)
                if rect.width >= 3, rect.height >= 3 {
                    onFinish?(rect)
                    return
                }
            }
            NSSound.beep()
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        NSColor.black.withAlphaComponent(0.34).setFill()
        bounds.fill()

        if let anchor, let cursorPoint {
            let rect = normalised(anchor, cursorPoint)
            if rect.width >= 1, rect.height >= 1 {
                // Punch the selection out of the dim layer so the shot area reads as "live".
                context.setBlendMode(.clear)
                context.fill(rect)
                context.setBlendMode(.normal)

                NSColor.white.setStroke()
                let outline = NSBezierPath(rect: rect)
                outline.lineWidth = 1
                outline.stroke()

                NSColor.systemBlue.withAlphaComponent(0.12).setFill()
                rect.fill()

                drawSizeTag(for: rect)
            }
            drawCrosshair(at: cursorPoint)
        }

        drawHint()
    }

    private func drawSizeTag(for rect: NSRect) {
        let text = "\(Int(rect.width)) × \(Int(rect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let padding = NSSize(width: 8, height: 4)
        var origin = NSPoint(x: rect.minX, y: rect.maxY + 6)
        if origin.y + size.height + padding.height * 2 > bounds.maxY {
            origin.y = max(bounds.minY + 4, rect.minY - size.height - padding.height * 2 - 6)
        }
        if origin.x + size.width + padding.width * 2 > bounds.maxX {
            origin.x = bounds.maxX - size.width - padding.width * 2 - 4
        }
        let box = NSRect(x: origin.x,
                         y: origin.y,
                         width: size.width + padding.width * 2,
                         height: size.height + padding.height * 2)
        NSColor.black.withAlphaComponent(0.62).setFill()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        (text as NSString).draw(at: NSPoint(x: box.minX + padding.width, y: box.minY + padding.height),
                                withAttributes: attributes)
    }

    private func drawCrosshair(at point: NSPoint) {
        NSColor.white.withAlphaComponent(0.55).setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: bounds.minX, y: point.y))
        path.line(to: NSPoint(x: bounds.maxX, y: point.y))
        path.move(to: NSPoint(x: point.x, y: bounds.minY))
        path.line(to: NSPoint(x: point.x, y: bounds.maxY))
        path.lineWidth = 0.5
        path.stroke()
    }

    private func drawHint() {
        let text = "拖动框选区域 · 也可以点击两次定角 · 回车完成 · Esc 取消"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.9),
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let padding = NSSize(width: 14, height: 7)
        let box = NSRect(x: bounds.midX - (size.width + padding.width * 2) / 2,
                         y: bounds.maxY - size.height - padding.height * 2 - 48,
                         width: size.width + padding.width * 2,
                         height: size.height + padding.height * 2)
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: box, xRadius: 9, yRadius: 9).fill()
        (text as NSString).draw(at: NSPoint(x: box.minX + padding.width, y: box.minY + padding.height),
                                withAttributes: attributes)
    }

    private func normalised(_ a: NSPoint, _ b: NSPoint) -> NSRect {
        NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}

// MARK: - Capture

enum ScreenshotCapture {
    /// Grabs the on-screen contents of the whole display and crops the requested rectangle.
    /// The rectangle is in screen coordinates (origin bottom-left), same as `NSScreen.frame`.
    static func image(for rect: NSRect, on screen: NSScreen) -> NSImage? {
        let clipped = rect.intersection(screen.frame)
        guard clipped.width >= 1, clipped.height >= 1 else { return nil }

        guard let cgImage = CGWindowListCreateImage(screen.frame,
                                                    .optionOnScreenOnly,
                                                    kCGNullWindowID,
                                                    [.bestResolution]) else { return nil }

        let full = NSImage(cgImage: cgImage, size: screen.frame.size)
        // Crop through AppKit so the display's backing scale and the bottom-left origin are
        // handled for us; feeding a pixel rect to CGImage would need a manual flip.
        let source = NSRect(x: clipped.minX - screen.frame.minX,
                            y: clipped.minY - screen.frame.minY,
                            width: clipped.width,
                            height: clipped.height)
        return NSImage(size: clipped.size, flipped: false) { destination in
            full.draw(in: destination, from: source, operation: .copy, fraction: 1)
            return true
        }
    }

    /// Both PNG and TIFF so every receiving app (and Preview, Pages, browser inputs) can paste.
    @discardableResult
    static func copy(_ image: NSImage) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        var copied = false
        if let tiff = image.tiffRepresentation {
            copied = pasteboard.setData(tiff, forType: .tiff) || copied
            if let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                copied = pasteboard.setData(png, forType: .png) || copied
            }
        }
        return copied
    }
}

// MARK: - Toast

/// Small non-activating confirmation badge so the user can tell the shot landed on the clipboard.
@MainActor
enum ScreenshotToast {
    static func show(_ message: String, duration: TimeInterval = 1.4) {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let label = NSTextField(labelWithString: message)
        label.font = attributes[.font] as? NSFont
        label.textColor = .white
        label.alignment = .center
        // Measure through the field itself: NSString.size omits the cell insets and clipped the
        // trailing digit of the size label.
        label.sizeToFit()
        let textSize = label.frame.size
        let padding = NSSize(width: 18, height: 11)
        let size = NSSize(width: textSize.width + padding.width * 2,
                          height: textSize.height + padding.height * 2)

        let frame = NSRect(x: screen.frame.midX - size.width / 2,
                           y: screen.frame.maxY - size.height - 90,
                           width: size.width,
                           height: size.height)
        let panel = ToastPanel(frame: frame)
        label.frame = NSRect(x: padding.width, y: padding.height,
                             width: textSize.width, height: textSize.height)

        let container = ToastView(frame: NSRect(origin: .zero, size: size))
        container.addSubview(label)
        panel.contentView = container
        panel.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                panel.animator().alphaValue = 0
            } completionHandler: {
                panel.orderOut(nil)
            }
        }
    }
}

private final class ToastPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(frame: NSRect) {
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
    }
}

private final class ToastView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
    }
}