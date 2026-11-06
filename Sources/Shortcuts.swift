import AppKit
import Carbon

struct Shortcut: Codable, Equatable {
    let key: UInt32
    let modifiers: UInt32
    let label: String
    var display: String {
        (modifiers & UInt32(controlKey) != 0 ? "⌃" : "") +
        (modifiers & UInt32(optionKey) != 0 ? "⌥" : "") +
        (modifiers & UInt32(shiftKey) != 0 ? "⇧" : "") +
        (modifiers & UInt32(cmdKey) != 0 ? "⌘" : "") + label
    }
    var isSafe: Bool {
        let allowed=UInt32(controlKey|optionKey|cmdKey|shiftKey)
        let major=[controlKey,optionKey,cmdKey].filter { modifiers & UInt32($0) != 0 }.count
        return major >= 2 && modifiers & ~allowed == 0
    }
    func isSafe(for action: String) -> Bool {
        isSafe || (action == "autoToggle" && key == 1 && modifiers == UInt32(controlKey))
    }
    func matches(_ other: Shortcut) -> Bool { key == other.key && modifiers == other.modifiers }
    static func from(_ event: NSEvent, action: String? = nil) -> Shortcut? {
        let f = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: UInt32 = f.contains(.option) ? UInt32(optionKey) : 0
        if f.contains(.control) { mods |= UInt32(controlKey) }
        if f.contains(.command) { mods |= UInt32(cmdKey) }
        if f.contains(.shift) { mods |= UInt32(shiftKey) }
        let names: [UInt16:String] = [123:"←",124:"→",125:"↓",126:"↑",36:"↩",49:"Space",48:"Tab",51:"⌫",117:"⌦",115:"Home",119:"End",116:"PageUp",121:"PageDown"]
        let label = names[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        let shortcut=Shortcut(key: UInt32(event.keyCode), modifiers: mods, label: label)
        return shortcut.isSafe(for:action ?? "") ? shortcut : nil
    }
    static var defaults: [String: Shortcut] {
        let base = UInt32(controlKey | optionKey), extra = UInt32(controlKey | optionKey | cmdKey)
        let specs: [(String, UInt32, String)] = [
            ("left",123,"←"),("right",124,"→"),("top",126,"↑"),("bottom",125,"↓"),
            ("topLeft",32,"U"),("topRight",34,"I"),("bottomLeft",38,"J"),("bottomRight",40,"K"),
            ("firstThird",2,"D"),("middleThird",3,"F"),("lastThird",5,"G"),
            ("leftTwoThirds",14,"E"),("rightTwoThirds",17,"T"),("maximize",36,"↩"),("center",8,"C"),("restore",6,"Z"),("palette",49,"Space")]
        var result = Dictionary(uniqueKeysWithValues: specs.map { ($0.0, Shortcut(key: $0.1, modifiers: base, label: $0.2)) })
        result["autoToggle"] = Shortcut(key:1, modifiers:UInt32(controlKey), label:"S")
        result["next"] = Shortcut(key:124, modifiers:extra, label:"→")
        result["previous"] = Shortcut(key:123, modifiers:extra, label:"←")
        result["undo"] = Shortcut(key:6, modifiers:extra, label:"Z")
        result["workspace"] = Shortcut(key:36, modifiers:extra, label:"↩")
        return result
    }
    // The automation switch remains reachable when manual shortcuts are disabled.
    static func activeBindings(_ shortcuts: [String:Shortcut], manualEnabled: Bool, paused: Bool) -> [String:Shortcut] {
        shortcuts.filter { $0.key == "autoToggle" || (manualEnabled && !paused) }
    }
}

final class HotKeyManager {
    var onAction: ((String) -> Void)?
    private var refs: [EventHotKeyRef] = []
    private var mapping: [UInt32:String] = [:]
    private var handler: EventHandlerRef?
    private var heldSwitches: Set<UInt32> = []
    private let signature: OSType = 0x51465031 // QFP1
    init() {
        var events = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                      EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event = event, let context = context else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(context).takeUnretainedValue()
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == manager.signature, let action = manager.mapping[id.id] else { return OSStatus(eventNotHandledErr) }
            let released=GetEventKind(event) == UInt32(kEventHotKeyReleased)
            if action == "autoToggle" {
                if released {
                    if manager.heldSwitches.remove(id.id) != nil { manager.onAction?(action) }
                } else { manager.heldSwitches.insert(id.id) }
                return noErr
            }
            if !released { manager.onAction?(action) }
            return noErr
        }, 2, &events, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func clear() { refs.forEach { UnregisterEventHotKey($0) }; refs.removeAll(); mapping.removeAll(); heldSwitches.removeAll() }
    @discardableResult func register(_ shortcuts: [String:Shortcut]) -> [String] {
        clear()
        var failures: [String] = []
        for (i, action) in shortcuts.keys.sorted().enumerated() {
            let shortcut = shortcuts[action]!
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: signature, id: UInt32(i+1))
            let result = RegisterEventHotKey(shortcut.key, shortcut.modifiers, id, GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &ref)
            if result == noErr, let ref = ref { refs.append(ref); mapping[id.id] = action }
            else { failures.append("\(actionTitle(action)) \(shortcut.display)（\(result)）") }
        }
        return failures
    }
    deinit { clear(); if let handler = handler { RemoveEventHandler(handler) } }
}

func actionTitle(_ action: String) -> String {
    if let layout = Layout(rawValue: action) { return layout.title }
    return ["autoToggle":"开启／关闭自动分屏", "next":"移到下一显示器", "previous":"移到上一显示器", "restore":"恢复原始位置", "undo":"撤销上次操作", "palette":"打开布局面板", "workspace":"打开工作布局"][action] ?? action
}

final class ShortcutCaptureView: NSView {
    var onKey: ((NSEvent) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { onKey?(event) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { onKey?(event); return true }
}

final class ShortcutPanel: NSPanel, NSWindowDelegate {
    var completion: ((Shortcut?) -> Void)?
    private var finished = false
    private let message = NSTextField(labelWithString: "同时按下 ⌃⌘、⌃⌥ 或 ⌘⌥ 和一个键。Esc 取消。")
    init(action: String) {
        super.init(contentRect: NSRect(x:0,y:0,width:460,height:140), styleMask:[.titled,.closable], backing:.buffered, defer:false)
        if action == "autoToggle" { message.stringValue="按 Control＋S，或使用两个修饰键的组合。Esc 取消。" }
        title = "设置快捷键 · \(actionTitle(action))"; delegate = self; isReleasedWhenClosed = false
        Theme.apply(to:self)
        let view = ShortcutCaptureView(frame: NSRect(x:0,y:0,width:460,height:140))
        message.frame = NSRect(x:20,y:52,width:420,height:44); message.maximumNumberOfLines = 2
        view.addSubview(message); contentView = view
        view.onKey = { [weak self] event in
            guard let self = self else { return }
            if event.keyCode == 53 { self.finish(nil); return }
            guard let shortcut = Shortcut.from(event,action:action) else { self.message.stringValue = "请包含 Control、Option、Command 中的至少两个键，避免占用普通输入。"; return }
            self.finish(shortcut)
        }
        initialFirstResponder = view; center()
    }
    private func finish(_ shortcut: Shortcut?) {
        guard !finished else { return }; finished = true
        close(); completion?(shortcut)
    }
    func windowWillClose(_ notification: Notification) { if !finished { finished = true; completion?(nil) } }
    func windowDidResignKey(_ notification: Notification) { finish(nil) }
}
