import AppKit

final class SnapPreview: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false; ignoresMouseEvents = true
        level = .floating; collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let view = NSView(); Theme.styleSnapOverlay(view)
        contentView = view
    }
    func show(_ ax: CGRect, desktopTop: CGFloat) {
        setFrame(Geometry.cocoaRect(ax, desktopTop: desktopTop), display: true); orderFrontRegardless()
    }
}

final class DragSnap {
    let engine: WindowEngine
    var enabled = true { didSet { if !enabled { reset() } } }
    var onFailure: ((String) -> Void)?
    private var monitor: Any?
    private var active: WindowHandle?
    private var start: CGRect?
    private var pressPoint: CGPoint?
    private var pending: (Display, Layout)?
    private var lastTick = Date.distantPast
    private let preview = SnapPreview()
    init(engine: WindowEngine) { self.engine = engine }
    func startMonitoring() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in self?.handle(event) }
    }
    func stopMonitoring() { if let monitor = monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; reset() }
    private func reset() { active = nil; start = nil; pressPoint = nil; pending = nil; preview.orderOut(nil) }
    private func handle(_ event: NSEvent) {
        guard enabled, engine.trusted else { reset(); return }
        if event.type == .leftMouseDown {
            reset()
            pressPoint = NSEvent.mouseLocation
            return
        }
        if event.type == .leftMouseDragged, active == nil, let down = pressPoint {
            let point = NSEvent.mouseLocation
            guard abs(point.x-down.x) > 4 || abs(point.y-down.y) > 4 else { return }
            // Ordinary clicks never perform an AX hit-test.
            pressPoint = nil
            if let window = engine.window(at: point), let rect = engine.frame(window) { active = window; start = rect }
            return
        }
        guard let window = active, let initial = start else { return }
        if event.type == .leftMouseUp {
            let target = pending
            reset()
            // Re-evaluate pointer and movement at release, not an old preview.
            guard let current = engine.frame(window), Geometry.isMove(start: initial, current: current), let target = target else { return }
            let p = NSEvent.mouseLocation, axPoint = CGPoint(x:p.x,y:engine.desktopTop-p.y)
            guard Geometry.snap(at: axPoint, display: target.0) == target.1 else { return }
            do { _ = try engine.layout(target.1, window: window, displayID: target.0.id) } catch { onFailure?(error.localizedDescription) }
            return
        }
        guard event.type == .leftMouseDragged, Date().timeIntervalSince(lastTick) > 0.045 else { return }
        lastTick = Date()
        guard let current = engine.frame(window), Geometry.isMove(start: initial, current: current) else { pending = nil; preview.orderOut(nil); return }
        let p = NSEvent.mouseLocation, point = CGPoint(x:p.x,y:engine.desktopTop-p.y)
        guard let display = engine.displays.first(where: { $0.full.contains(point) }), let layout = Geometry.snap(at: point, display: display) else {
            pending = nil; preview.orderOut(nil); return
        }
        pending = (display, layout)
        preview.show(Geometry.target(layout, current: current, on: display, gap: engine.gap), desktopTop: engine.desktopTop)
    }
    deinit { stopMonitoring() }
}
