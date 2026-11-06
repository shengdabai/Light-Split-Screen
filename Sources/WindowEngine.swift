import AppKit
import ApplicationServices

struct WindowFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class WindowHandle {
    let element: AXUIElement
    let pid: pid_t
    let launched: Date?
    let appName: String
    let bundleID: String
    let title: String
    init(_ element: AXUIElement, app: NSRunningApplication, title: String) {
        self.element = element; self.pid = app.processIdentifier; self.launched = app.launchDate
        self.appName = app.localizedName ?? "应用"; self.bundleID = app.bundleIdentifier ?? ""
        self.title = String(title.prefix(100))
        AXUIElementSetMessagingTimeout(element, 0.3)
    }
    func same(as other: WindowHandle) -> Bool {
        pid == other.pid && launched == other.launched && CFEqual(element, other.element)
    }
    var label: String { title.isEmpty ? appName : "\(appName) · \(title)" }
}

final class WindowEngine {
    struct Snapshot { let window: WindowHandle; let frame: CGRect }
    var excluded: Set<String> = []
    var gap: CGFloat = 8 {
        didSet { gap = Geometry.normalizedGap(gap) }
    }
    private var history: [[Snapshot]] = []
    private var originals: [Snapshot] = []
    var desktopTop: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }
    var displays: [Display] {
        NSScreen.screens.map { screen in
            Display(id: (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0,
                    full: Geometry.axRect(screen.frame, desktopTop: desktopTop),
                    visible: Geometry.axRect(screen.visibleFrame, desktopTop: desktopTop), scale: screen.backingScaleFactor)
        }
    }
    var trusted: Bool { AXIsProcessTrusted() }
    var canUndo: Bool { !history.isEmpty }
    func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
        return result
    }
    func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value = value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    func frame(_ window: WindowHandle) -> CGRect? {
        guard let pos = attribute(window.element, kAXPositionAttribute), let size = attribute(window.element, kAXSizeAttribute),
              CFGetTypeID(pos) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        guard AXValueGetValue(pos as! AXValue, .cgPoint, &p), AXValueGetValue(size as! AXValue, .cgSize, &s),
              p.x.isFinite, p.y.isFinite, s.width.isFinite, s.height.isFinite, s.width > 0, s.height > 0 else { return nil }
        return CGRect(origin: p, size: s)
    }
    func validate(_ w: WindowHandle) throws {
        guard trusted else { throw WindowFailure(message: "请先在系统设置中允许轻分屏使用辅助功能。") }
        guard let app = NSRunningApplication(processIdentifier: w.pid), app.launchDate == w.launched, !app.isTerminated else {
            throw WindowFailure(message: "这个窗口所属的应用已退出，请重新选择。")
        }
        guard w.pid != ProcessInfo.processInfo.processIdentifier, !excluded.contains(w.bundleID) else {
            throw WindowFailure(message: "这个应用已被排除。")
        }
        guard app.activationPolicy == .regular,
              attribute(w.element, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole else {
            throw WindowFailure(message: "只调整普通软件窗口；浮动面板和对话框不会吸附。")
        }
        guard (attribute(w.element, kAXMinimizedAttribute) as? Bool) != true,
              (attribute(w.element, "AXFullScreen") as? Bool) != true else {
            throw WindowFailure(message: "请先退出系统全屏或还原最小化窗口。")
        }
        var movable = DarwinBoolean(false), resizable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(w.element, kAXPositionAttribute as CFString, &movable) == .success,
              AXUIElementIsAttributeSettable(w.element, kAXSizeAttribute as CFString, &resizable) == .success,
              movable.boolValue, resizable.boolValue, frame(w) != nil else {
            throw WindowFailure(message: "\(w.appName) 的这个窗口不允许移动或调整尺寸。")
        }
    }
    func handle(_ element: AXUIElement, app: NSRunningApplication) -> WindowHandle {
        WindowHandle(element, app: app, title: attribute(element, kAXTitleAttribute) as? String ?? "")
    }
    func focused(pid: pid_t?) -> WindowHandle? {
        guard trusted, let pid = pid, let app = NSRunningApplication(processIdentifier: pid), pid != ProcessInfo.processInfo.processIdentifier else { return nil }
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.3)
        guard let focused = element(attribute(root, kAXFocusedWindowAttribute)) ?? element(attribute(root, kAXMainWindowAttribute)) else { return nil }
        return handle(focused, app: app)
    }
    func window(at cocoa: CGPoint) -> WindowHandle? {
        guard trusted else { return nil }
        var hit: AXUIElement?
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2)
        guard AXUIElementCopyElementAtPosition(system, Float(cocoa.x), Float(desktopTop-cocoa.y), &hit) == .success, var node = hit else { return nil }
        // Traverse only bounded ancestors. No text fields or contents are collected.
        for _ in 0..<12 {
            if attribute(node, kAXRoleAttribute) as? String == kAXWindowRole {
                var pid: pid_t = 0
                guard AXUIElementGetPid(node, &pid) == .success, let app = NSRunningApplication(processIdentifier: pid) else { return nil }
                let w = handle(node, app: app)
                do { try validate(w); return w } catch { return nil }
            }
            guard let parent = element(attribute(node, kAXParentAttribute)), !CFEqual(parent, node) else { break }
            node = parent
        }
        return nil
    }
    func windows() -> [WindowHandle] {
        guard trusted else { return [] }
        var result: [WindowHandle] = []
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        for app in apps.sorted(by: { ($0.localizedName ?? "") < ($1.localizedName ?? "") }) where !excluded.contains(app.bundleIdentifier ?? "") {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.2)
            guard let list = attribute(root, kAXWindowsAttribute) as? [AnyObject] else { continue }
            for raw in list.prefix(30) {
                guard let item=element(raw) else { continue }
                guard attribute(item, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole else { continue }
                let w = handle(item, app: app)
                if (try? validate(w)) != nil { result.append(w) }
            }
        }
        return result
    }
    private func write(_ w: WindowHandle, to target: CGRect) -> String? {
        var p = target.origin, s = target.size
        guard let pos = AXValueCreate(.cgPoint, &p), let size = AXValueCreate(.cgSize, &s) else { return "无法创建窗口坐标。" }
        // AppKit updates a window's destination-screen constraints asynchronously.
        // Re-submit after a short delay; merely waiting and reading retains the old clamp.
        var lastError = AXError.success
        for _ in 0..<5 {
            let sizeResult = AXUIElementSetAttributeValue(w.element, kAXSizeAttribute as CFString, size)
            if sizeResult == .cannotComplete || sizeResult == .invalidUIElement || sizeResult == .apiDisabled {
                return "\(w.appName) 暂时无法响应窗口调整。"
            }
            let positionResult = AXUIElementSetAttributeValue(w.element, kAXPositionAttribute as CFString, pos)
            if positionResult == .cannotComplete || positionResult == .invalidUIElement || positionResult == .apiDisabled {
                return "\(w.appName) 暂时无法响应窗口调整。"
            }
            if sizeResult != .success { lastError = sizeResult }
            if positionResult != .success { lastError = positionResult }
            usleep(50_000)
            if let actual = frame(w), Geometry.accepts(actual, target: target) { return nil }
        }
        if lastError != .success { return "\(w.appName) 拒绝调整窗口（AX \(lastError.rawValue)）。" }
        return "\(w.appName) 的最小尺寸或应用规则限制了布局。"
    }
    @discardableResult func apply(_ plan: [(WindowHandle, CGRect)]) throws -> String {
        guard !plan.isEmpty else { throw WindowFailure(message: "请先选择窗口。") }
        var before: [Snapshot] = []
        for (w, rect) in plan {
            try validate(w)
            guard rect.width > 0, rect.height > 0, !rect.isInfinite, !rect.isNull, let old = frame(w) else { throw WindowFailure(message: "窗口坐标不可用。") }
            before.append(Snapshot(window: w, frame: old))
        }
        // Keep a bounded undo record even if a resize fails partway through.
        history.append(before); if history.count > 30 { history.removeFirst() }
        for item in before where !originals.contains(where: { $0.window.same(as: item.window) }) {
            originals.append(item); if originals.count > 80 { originals.removeFirst() }
        }
        for (w, target) in plan {
            if let error = write(w, to: target) {
                var rollbackFailed = false
                for snapshot in before { if write(snapshot.window, to: snapshot.frame) != nil { rollbackFailed = true } }
                if !rollbackFailed { history.removeLast() }
                throw WindowFailure(message: error + (rollbackFailed ? " 部分窗口未恢复，可使用“撤销上次操作”重试。" : " 已恢复本次操作前的尺寸。"))
            }
        }
        return "已调整 \(plan.count) 个窗口。"
    }
    func layout(_ layout: Layout, window: WindowHandle, displayID: UInt32? = nil) throws -> String {
        guard let rect = frame(window) else { throw WindowFailure(message: "找不到窗口。") }
        let display = displayID.flatMap { id in displays.first(where: { $0.id == id }) } ?? (displayID == nil ? Geometry.display(for: rect, among: displays) : nil)
        guard let display = display else { throw WindowFailure(message: "显示器已断开，请重试。") }
        return try apply([(window, Geometry.target(layout, current: rect, on: display, gap: gap))])
    }
    func transfer(_ window: WindowHandle, direction: Int) throws -> String {
        let all = displays.sorted { $0.full.minX == $1.full.minX ? $0.full.minY < $1.full.minY : $0.full.minX < $1.full.minX }
        guard all.count > 1 else { throw WindowFailure(message: "当前只有一台显示器。") }
        guard let rect = frame(window), let source = Geometry.display(for: rect, among: all), let i = all.firstIndex(where: { $0.id == source.id }) else { throw WindowFailure(message: "找不到显示器。") }
        let destination = all[(i + direction + all.count) % all.count]
        return try apply([(window, Geometry.transferred(rect, from: source, to: destination))])
    }
    func restore(_ window: WindowHandle) throws -> String {
        guard let original = originals.first(where: { $0.window.same(as: window) }), let display = Geometry.display(for: original.frame, among: displays) else { throw WindowFailure(message: "这个窗口还没有可恢复的原始位置。") }
        return try apply([(window, Geometry.clamp(original.frame, to: display.visible))])
    }
    func undo() throws -> String {
        guard trusted else { throw WindowFailure(message: "请先允许轻分屏使用辅助功能。") }
        guard let batch = history.last else { throw WindowFailure(message: "还没有可撤销的操作。") }
        var failed: [Snapshot] = []
        var skipped = 0
        for item in batch {
            do {
                try validate(item.window)
                guard let display = Geometry.display(for: item.frame, among: displays) else { throw WindowFailure(message: "无可用显示器") }
                if write(item.window, to: Geometry.clamp(item.frame, to: display.visible)) != nil { failed.append(item) }
            } catch { skipped += 1 }
        }
        if failed.isEmpty { history.removeLast(); return skipped == 0 ? "已撤销上次操作。" : "已撤销；跳过 \(skipped) 个已关闭或不再允许调整的窗口。" }
        history[history.count-1] = failed
        throw WindowFailure(message: "部分窗口拒绝调整；已保留其撤销记录。关闭或排除的窗口已跳过。")
    }
}
