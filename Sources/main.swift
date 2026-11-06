import AppKit

final class FlippedDocument: NSView {
    override var isFlipped: Bool { true }
}

final class WorkspacePreview: NSView {
    var workspace: Workspace = .compare { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        Theme.drawPreview(workspace.units, in: bounds)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let engine = WindowEngine()
    let hotKeys = HotKeyManager()
    lazy var drag = DragSnap(engine: engine)
    lazy var automatic = AutoArrange(engine:engine,scopePID:fixturePID)
    var autoState = AutoArrange.State()
    var autoWanted = false
    var dashboard: DashboardController?
    let popover = NSPopover()
    var dashboardPanel: NSPanel?
    var selectedSettingsTab = 0
    var ignoredAppsPanel: NSPanel?
    var fixturePID: pid_t? {
        guard let i=CommandLine.arguments.firstIndex(of:"--fixture-pid"),CommandLine.arguments.indices.contains(i+1) else { return nil }
        return Int32(CommandLine.arguments[i+1])
    }
    var status: NSStatusItem!
    var observer: NSObjectProtocol?
    var lastExternalPID: pid_t?
    var target: WindowHandle?
    var paletteTarget: WindowHandle?
    var paused = false
    var shortcuts = Shortcut.defaults
    var shortcutFailures: [String] = []
    var palette: NSPanel?
    var settings: NSPanel?
    var workspacePanel: NSPanel?
    var capture: ShortcutPanel?
    var workspaceChoices: [NSPopUpButton] = []
    var workspaceCandidates: [WindowHandle] = []
    var screenChoices = NSPopUpButton()
    var workspacePicker = NSPopUpButton()
    var workspacePreview = WorkspacePreview()
    var workspaceScreens: [Display] = []
    var gapField: NSTextField?
    var exclusionsField: NSTextField?
    var preferenceStatus: NSTextField?
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults=defaults;super.init() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--fixture-pid"), fixturePID == nil || fixturePID! <= 0 {
            fputs("Invalid --fixture-pid; no window management started.\n",stderr);exit(2)
        }
        Theme.forceLight()
        NSApp.setActivationPolicy(.accessory)
        if let data = defaults.data(forKey:"shortcuts"), let loaded = try? JSONDecoder().decode([String:Shortcut].self,from:data) {
            for key in shortcuts.keys { if let value = loaded[key], value.isSafe(for:key) { shortcuts[key] = value } }
        }
        engine.gap = CGFloat(defaults.object(forKey:"gap") as? Double ?? 8)
        engine.excluded = Set(defaults.stringArray(forKey:"excluded") ?? [])
        drag.enabled = false
        hotKeys.onAction = { [weak self] action in self?.run(action, fresh:true) }
        drag.onFailure = { [weak self] message in self?.setStatus(message) }
        lastExternalPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier, app.activationPolicy == .regular else { return }
            self?.lastExternalPID = app.processIdentifier
        }
        status = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        status.button?.image = .qfpMark()
        status.button?.toolTip = "轻分屏 · 窗口布局"
        status.button?.target=self;status.button?.action = #selector(trayAction(_:))
        status.button?.sendAction(on:[.leftMouseUp,.rightMouseUp])
        automatic.onChange = { [weak self] state in
            guard let self=self else { return };self.autoState=state;self.updateDashboard();self.setStatus(state.message)
        }
        // Login starts only the menu-bar switch. Window control always requires
        // an explicit action in this process, even if the previous run was on.
        autoWanted=false;defaults.set(false,forKey:"continuousAuto")
        refreshKeys();syncAutomatic()
        if CommandLine.arguments.contains("--show-settings") { showSettings() }
        if CommandLine.arguments.contains("--show-dashboard") { showPalette() }
        if CommandLine.arguments.contains("--smoke-test") {
            showPalette()
            DispatchQueue.main.asyncAfter(deadline:.now()+2) { print("UI_SMOKE_READY trusted=\(self.engine.trusted) screens=\(self.engine.displays.count) shortcutsFailed=\(self.shortcutFailures.count)"); fflush(stdout) }
        }
    }
    func applicationWillTerminate(_ notification: Notification) { automatic.setEnabled(false);drag.stopMonitoring(); hotKeys.clear(); if let observer = observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) } }
    func refreshKeys() {
        shortcutFailures=hotKeys.register(Shortcut.activeBindings(shortcuts,manualEnabled:defaults.bool(forKey:"hotkeysEnabled"),paused:paused))
    }
    func setStatus(_ message: String) { status.button?.toolTip = "轻分屏 · " + message; preferenceStatus?.stringValue = message }
    func currentTarget(fresh: Bool) -> WindowHandle? {
        if fresh { target = engine.focused(pid:lastExternalPID) }
        return target
    }
    func menuWillOpen(_ menu: NSMenu) {
        target = engine.focused(pid:lastExternalPID)
        menu.removeAllItems()
        add(menu,"轻分屏  ·  " + (paused ? "已暂停" : engine.trusted ? "就绪" : "等待辅助功能权限"),nil,enabled:false)
        if let target = target { add(menu,String(target.label.prefix(60)),nil,enabled:false) }
        menu.addItem(.separator())
        add(menu,"打开布局面板","palette"); add(menu,"工作布局 · 选择 2–4 个窗口","workspace")
        add(menu,autoWanted ? "关闭自动分屏" : "开启自动分屏","autoToggle")
        add(menu,"立即整理当前桌面","autoNow")
        add(menu,"撤销并暂停","autoUndo",enabled:engine.canUndo)
        let manual=NSMenu();for layout in Layout.allCases { add(manual,layout.title,layout.rawValue,enabled:engine.trusted && !paused && target != nil) }
        let manualItem=NSMenuItem(title:"手动调整当前窗口",action:nil,keyEquivalent:"");manualItem.submenu=manual;menu.addItem(manualItem)
        menu.addItem(.separator())
        for action in ["previous","next","restore","undo"] { add(menu,actionTitle(action),action,enabled:engine.trusted && !paused) }
        menu.addItem(.separator())
        add(menu,paused ? "继续管理窗口" : "暂停管理窗口","pause")
        add(menu,"设置与权限…","settings")
        if !shortcutFailures.isEmpty { add(menu,"⚠ \(shortcutFailures.count) 个快捷键被占用，打开设置更改","settings") }
        add(menu,"退出轻分屏","quit")
    }
    func add(_ menu: NSMenu, _ title: String, _ action: String?, enabled: Bool = true) {
        let suffix = (action == "autoToggle" || defaults.bool(forKey:"hotkeysEnabled")) ? (action.flatMap { shortcuts[$0]?.display }.map { "    \($0)" } ?? "") : ""
        let item = NSMenuItem(title:title+suffix,action:action == nil ? nil : #selector(menuAction(_:)),keyEquivalent:"")
        item.target = self; item.representedObject = action; item.isEnabled = enabled; menu.addItem(item)
    }
    @objc func menuAction(_ sender: NSMenuItem) { if let action = sender.representedObject as? String { run(action,fresh:false) } }
    @objc func buttonAction(_ sender: NSButton) {
        if let action = sender.identifier?.rawValue {
            if sender.window === palette { target = paletteTarget }
            run(action,fresh:false)
        }
    }
    func run(_ action: String, fresh: Bool) {
        switch action {
        case "quit": NSApp.terminate(nil); return
        case "settings": popover.close();showSettings(); return
        case "autoToggle": setAutomatic(!autoWanted);return
        case "autoNow": arrangeNow();return
        case "autoUndo": undoAndPause();return
        case "pause": if !paused { setAutomatic(false) };paused.toggle();syncAutomatic();refreshKeys();return
        case "palette": if fresh { target = engine.focused(pid:lastExternalPID) }; showPalette(); return
        case "workspace":
            guard !paused else { report("轻分屏已暂停。请在菜单栏继续管理窗口。"); return }
            showWorkspace(); return
        default: break
        }
        guard !paused else { report("轻分屏已暂停。请在菜单栏继续管理窗口。"); return }
        guard engine.trusted else { showSettings(); return }
        if autoWanted { setAutomatic(false) }
        do {
            if action == "undo" { report(try engine.undo(),alert:false); return }
            guard let window = currentTarget(fresh:fresh) else { throw WindowFailure(message:"请先点选要调整的软件窗口，再使用快捷键或菜单栏。") }
            let result: String
            if let layout = Layout(rawValue:action) { result = try engine.layout(layout,window:window) }
            else if action == "restore" { result = try engine.restore(window) }
            else if action == "next" || action == "previous" { result = try engine.transfer(window,direction:action == "next" ? 1 : -1) }
            else { return }
            palette?.orderOut(nil)
            NSRunningApplication(processIdentifier:window.pid)?.activate(options:[])
            report(result,alert:false)
        } catch { report(error.localizedDescription) }
    }
    func report(_ message: String, alert: Bool = true) {
        setStatus(message)
        if alert { NSApp.activate(ignoringOtherApps:true); let box = NSAlert(); box.messageText = "轻分屏"; box.informativeText = message; box.addButton(withTitle:"知道了"); box.runModal() }
    }
    func label(_ text: String, _ kind: Theme.Text = .body) -> NSTextField {
        let f = NSTextField(wrappingLabelWithString:text); f.maximumNumberOfLines = 0; Theme.style(f,kind); return f
    }
    func button(_ title: String, action: String, role: Theme.Role = .secondary) -> NSButton {
        let b = NSButton(title:title,target:self,action:#selector(buttonAction(_:))); Theme.style(b,role); b.identifier = NSUserInterfaceItemIdentifier(action); return b
    }
    func stack(_ views: [NSView], horizontal: Bool = false) -> NSStackView {
        let s = NSStackView(views:views); s.orientation = horizontal ? .horizontal : .vertical; s.alignment = horizontal ? .centerY : .leading; s.spacing = Theme.rowGap; return s
    }
    func panel(title: String, width: CGFloat, height: CGFloat, content: NSView) -> NSPanel {
        let p = NSPanel(contentRect:NSRect(x:0,y:0,width:width,height:height),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        p.title = title; p.isReleasedWhenClosed = false; p.minSize = NSSize(width:width,height:280)
        Theme.apply(to:p); p.hidesOnDeactivate = false
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        let document = FlippedDocument(); content.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(content)
        scroll.documentView = document; p.contentView = scroll
        document.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor),
            content.leadingAnchor.constraint(equalTo:document.leadingAnchor,constant:Theme.padX),
            content.trailingAnchor.constraint(equalTo:document.trailingAnchor,constant:-Theme.padX),
            content.topAnchor.constraint(equalTo:document.topAnchor,constant:Theme.padTop),
            content.bottomAnchor.constraint(equalTo:document.bottomAnchor,constant:-Theme.padBottom)
        ])
        if let s = content as? NSStackView { Theme.fitLabels(in:s,width:Theme.wrapWidth(forPanel:width)) }
        p.center(); return p
    }
    func present(_ p: NSPanel?) { NSApp.activate(ignoringOtherApps:true); p?.makeKeyAndOrderFront(nil) }
    func syncAutomatic() {
        let preview=CommandLine.arguments.contains("--preview")
        automatic.setEnabled(autoWanted && !paused && !preview)
        drag.enabled=false;drag.stopMonitoring()
        if preview { autoState=AutoArrange.State(enabled:true,count:0,message:"界面预览 · 不调整窗口",preview:AutoLayout.units(count:3,aspect:1.6));updateDashboard() }
    }
    func setAutomatic(_ value: Bool) {
        autoWanted=value;defaults.set(value,forKey:"continuousAuto")
        let wasPaused=paused
        if value { paused=false }
        syncAutomatic()
        // Do not unregister the switch while its key is held.
        if wasPaused != paused { refreshKeys() }
        updateDashboard()
        if value && !engine.trusted { showPalette() }
    }
    func updateDashboard() {
        dashboard?.update(autoState,trusted:engine.trusted,canUndo:engine.canUndo)
        if let key=shortcuts["autoToggle"] {
            dashboard?.toggle.toolTip="\(key.display) 开启／关闭；每次启动默认关闭"
            if !autoWanted && engine.trusted {
                dashboard?.message.stringValue="按 \(key.display) 开启，再按一次关闭。关闭时不自动移动窗口。"
            }
        }
    }
    @objc func toggleAutomatic(_ sender: NSSwitch) { setAutomatic(sender.state == .on) }
    @objc func arrangeNow() {
        guard engine.trusted else { openAccessibility();return }
        if !autoWanted || paused { setAutomatic(true) }
        else if !automatic.isMonitoring { syncAutomatic() }
        else { automatic.refresh() }
    }
    @objc func undoAndPause() {
        setAutomatic(false)
        do { report(try engine.undo(),alert:false) } catch { report(error.localizedDescription,alert:false) }
        updateDashboard()
    }
    @objc func openSettingsAction() { popover.close();showSettings() }
    @objc func trayAction(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp { showManualMenu(sender);return }
        if popover.isShown { popover.close() } else { showPalette() }
    }
    @objc func showManualMenu(_ sender: NSView) {
        target=engine.focused(pid:lastExternalPID)
        let menu=NSMenu();menu.delegate=self;menuWillOpen(menu)
        menu.popUp(positioning:nil,at:NSPoint(x:0,y:sender.bounds.minY),in:sender)
    }
    func makeDashboard() -> DashboardController {
        let controller=DashboardController();_ = controller.view
        controller.toggle.target=self;controller.toggle.action = #selector(toggleAutomatic(_:))
        controller.primary.target=self;controller.primary.action = #selector(arrangeNow)
        controller.undo.target=self;controller.undo.action = #selector(undoAndPause)
        controller.more.target=self;controller.more.action = #selector(showManualMenu(_:))
        controller.settings.target=self;controller.settings.action = #selector(openSettingsAction)
        controller.update(autoState,trusted:engine.trusted,canUndo:engine.canUndo)
        dashboard=controller;updateDashboard();return controller
    }
    func showPalette() {
        popover.close();dashboardPanel?.close()
        let controller=makeDashboard()
        if CommandLine.arguments.contains("--show-dashboard") || CommandLine.arguments.contains("--smoke-test") {
            let p=NSPanel(contentRect:NSRect(x:0,y:0,width:336,height:316),styleMask:[.titled,.closable],backing:.buffered,defer:false)
            p.title="轻分屏";p.isReleasedWhenClosed=false;Theme.apply(to:p);p.contentViewController=controller;p.center();dashboardPanel=p;present(p)
        } else if let button=status.button {
            popover.contentViewController=controller;popover.contentSize=NSSize(width:336,height:316);popover.behavior = .transient
            popover.show(relativeTo:button.bounds,of:button,preferredEdge:.minY)
        }
    }
    @objc func settingsTabChanged(_ sender: NSSegmentedControl) { selectedSettingsTab=sender.selectedSegment;showSettings() }
    func showSettings() {
        let tabs=NSSegmentedControl(labels:["通用","快捷键"],trackingMode:.selectOne,target:self,action:#selector(settingsTabChanged(_:)))
        tabs.selectedSegment=selectedSettingsTab;tabs.segmentStyle = .rounded
        var rows: [NSView]=[tabs]
        exclusionsField=nil
        if selectedSettingsTab == 0 {
            let permission=label(engine.trusted ? "✓ 设备控制权限已生效" : "⚠ 设备控制权限未生效",.status(ok:engine.trusted))
            let open=NSButton(title:"系统设置…",target:self,action:#selector(openAccessibility));Theme.style(open,.secondary)
            let check=NSButton(title:"重新检测",target:self,action:#selector(recheckPermission));Theme.style(check,.secondary)
            let auto=NSButton(checkboxWithTitle:"打开或关闭窗口后，自动重新排列",target:self,action:#selector(toggleAutoCheckbox(_:)));auto.state=autoWanted ? .on : .off
            let gap=NSTextField(string:String(Int(engine.gap)));gap.widthAnchor.constraint(equalToConstant:48).isActive=true;gap.setAccessibilityLabel("窗口间距，点");gapField=gap
            let save=NSButton(title:"保存",target:self,action:#selector(savePreferences));Theme.style(save,.secondary)
            let ignore=NSButton(title:"忽略的应用…",target:self,action:#selector(showIgnoredApps));Theme.style(ignore,.secondary)
            let statusText=label(engine.trusted ? "只整理当前桌面，按显示器分别排列。" : "用于移动其他软件窗口。若系统开关已打开，请移除旧条目，再添加本应用。",.note);preferenceStatus=statusText
            rows += [permission,stack([open,check],horizontal:true),statusText,NSBox.separator(),auto,label("每次启动默认关闭。按 \(shortcuts["autoToggle"]?.display ?? "⌃S") 开启／关闭；关闭后不自动移动窗口。",.note),stack([label("窗口间距"),gap,label("点"),save],horizontal:true),ignore,label("关闭会停止窗口监听与待执行整理。拖边吸附已停用；设置仅保存在本机。",.note)]
        } else {
            let enabled=NSButton(checkboxWithTitle:"启用手动布局快捷键（可选）",target:self,action:#selector(toggleHotkeys(_:)));enabled.state=defaults.bool(forKey:"hotkeysEnabled") ? .on : .off
            rows.append(enabled)
            let statusText=label(shortcutFailures.isEmpty ? "开关默认 ⌃S，会接管全局 Control＋S；下方组合可更改。" : "部分按键被占用："+shortcutFailures.joined(separator:"、"),.note);preferenceStatus=statusText
            rows.append(statusText)
            for action in shortcuts.keys.sorted(by:{actionTitle($0) < actionTitle($1)}) {
                let name=label(actionTitle(action));name.widthAnchor.constraint(equalToConstant:180).isActive=true
                let change=NSButton(title:shortcuts[action]!.display,target:self,action:#selector(changeShortcut(_:)));change.identifier=NSUserInterfaceItemIdentifier(action);change.setAccessibilityLabel(actionTitle(action)+"："+shortcuts[action]!.display+"，点按更改");Theme.style(change,.secondary);change.widthAnchor.constraint(equalToConstant:120).isActive=true
                rows.append(stack([name,change],horizontal:true))
            }
            let reset=NSButton(title:"恢复默认快捷键",target:self,action:#selector(resetShortcuts));Theme.style(reset,.secondary);rows.append(reset)
        }
        let content=stack(Array(rows.dropFirst()))
        let p=NSPanel(contentRect:NSRect(x:0,y:0,width:420,height:selectedSettingsTab == 0 ? 360 : 410),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        p.title="轻分屏设置";p.isReleasedWhenClosed=false;Theme.apply(to:p)
        let root=NSView();root.addSubview(tabs);tabs.translatesAutoresizingMaskIntoConstraints=false
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;scroll.drawsBackground=false;scroll.translatesAutoresizingMaskIntoConstraints=false;root.addSubview(scroll)
        let document=FlippedDocument();document.translatesAutoresizingMaskIntoConstraints=false;scroll.documentView=document
        content.translatesAutoresizingMaskIntoConstraints=false;document.addSubview(content)
        NSLayoutConstraint.activate([tabs.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:20),tabs.topAnchor.constraint(equalTo:root.topAnchor,constant:14),scroll.topAnchor.constraint(equalTo:tabs.bottomAnchor,constant:14),scroll.leadingAnchor.constraint(equalTo:root.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:root.trailingAnchor),scroll.bottomAnchor.constraint(equalTo:root.bottomAnchor),document.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor),content.leadingAnchor.constraint(equalTo:document.leadingAnchor,constant:20),content.trailingAnchor.constraint(equalTo:document.trailingAnchor,constant:-20),content.topAnchor.constraint(equalTo:document.topAnchor),content.bottomAnchor.constraint(equalTo:document.bottomAnchor,constant:-16)])
        Theme.fitLabels(in:content,width:364)
        p.contentView=root;p.center();settings?.close();settings=p;present(settings)
    }
    @objc func toggleAutoCheckbox(_ sender: NSButton) { setAutomatic(sender.state == .on);showSettings() }
    @objc func toggleHotkeys(_ sender: NSButton) { defaults.set(sender.state == .on,forKey:"hotkeysEnabled");refreshKeys() }
    @objc func showIgnoredApps() {
        let apps=NSWorkspace.shared.runningApplications.filter {$0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier}.sorted {($0.localizedName ?? "") < ($1.localizedName ?? "")}
        var rows: [NSView]=[label("这些应用不会参与自动分屏",.section)]
        for app in apps {
            guard let id=app.bundleIdentifier else { continue }
            let b=NSButton(checkboxWithTitle:app.localizedName ?? id,target:self,action:#selector(toggleIgnoredApp(_:)));b.identifier=NSUserInterfaceItemIdentifier(id);b.state=engine.excluded.contains(id) ? .on : .off;rows.append(b)
        }
        ignoredAppsPanel?.close();ignoredAppsPanel=panel(title:"忽略的应用",width:320,height:340,content:stack(rows));present(ignoredAppsPanel)
    }
    @objc func toggleIgnoredApp(_ sender: NSButton) {
        guard let id=sender.identifier?.rawValue else { return }
        if sender.state == .on { engine.excluded.insert(id) } else { engine.excluded.remove(id) }
        defaults.set(engine.excluded.sorted(),forKey:"excluded");automatic.refresh()
    }
    @objc func openAccessibility() {
        // The user clicks this button; the application never grants itself access.
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary)
        if let url = URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
    @objc func recheckPermission() { syncAutomatic();showSettings();setStatus(engine.trusted ? "设备控制权限已生效。" : "权限未生效；请移除系统中的旧条目，再添加本应用。") }
    @objc func savePreferences() {
        guard let text = gapField?.stringValue, let value = Int(text), (0...32).contains(value) else { report("间距请输入 0–32 的整数。"); return }
        let ids = (exclusionsField?.stringValue ?? engine.excluded.sorted().joined(separator:",")).replacingOccurrences(of:"，",with:",").split(separator:",").map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard ids.allSatisfy({ $0.contains(".") && !$0.contains(" ") && $0.count <= 200 }) else { report("请用逗号分隔完整 bundle ID，例如 com.apple.finder。"); return }
        engine.gap = CGFloat(value); engine.excluded = Set(ids)
        defaults.set(value,forKey:"gap"); defaults.set(ids,forKey:"excluded"); setStatus("设置已保存。");automatic.refresh()
    }
    @objc func changeShortcut(_ sender: NSButton) {
        guard let action = sender.identifier?.rawValue else { return }
        if let existing = capture { present(existing); return }
        hotKeys.clear()
        let p = ShortcutPanel(action:action); capture = p
        p.completion = { [weak self] value in
            guard let self = self else { return }
            self.capture = nil
            if let value = value {
                if let duplicate = self.shortcuts.first(where:{ $0.key != action && $0.value.matches(value) }) {
                    self.refreshKeys(); self.report("此快捷键已用于“\(actionTitle(duplicate.key))”，原设置已保留。"); return
                }
                let old = self.shortcuts[action]
                self.shortcuts[action] = value; self.refreshKeys()
                if self.shortcutFailures.contains(where:{ $0.hasPrefix(actionTitle(action)+" ") }) {
                    self.shortcuts[action] = old; self.refreshKeys(); self.report("这个快捷键被系统或其他软件占用，原设置已保留。")
                } else { self.persistShortcuts() }
            } else {
                // Cancelling on focus loss must not reactivate the app and steal focus.
                self.refreshKeys(); return
            }
            self.showSettings()
        }
        present(p)
    }
    func persistShortcuts() { if let data = try? JSONEncoder().encode(shortcuts) { defaults.set(data,forKey:"shortcuts") } }
    @objc func resetShortcuts() { shortcuts = Shortcut.defaults; persistShortcuts(); refreshKeys(); showSettings() }
    func showWorkspace() {
        guard engine.trusted else { showSettings(); return }
        workspaceCandidates = engine.windows(); workspaceScreens = engine.displays
        guard workspaceCandidates.count >= 2 else { report("至少需要两个可调整的普通窗口。请先打开窗口，并退出系统全屏。"); return }
        workspacePicker = NSPopUpButton(); workspacePicker.addItems(withTitles:Workspace.allCases.map(\.title)); workspacePicker.target = self; workspacePicker.action = #selector(workspaceChanged)
        screenChoices = NSPopUpButton(); screenChoices.addItems(withTitles:workspaceScreens.enumerated().map { "显示器 \($0.offset+1) · \(Int($0.element.visible.width))×\(Int($0.element.visible.height))" })
        if let focus = engine.focused(pid:lastExternalPID), let rect = engine.frame(focus), let d = Geometry.display(for:rect,among:workspaceScreens), let i = workspaceScreens.firstIndex(where:{$0.id == d.id}) { screenChoices.selectItem(at:i) }
        workspaceChoices = (0..<4).map { i in
            let pick = NSPopUpButton(); pick.addItems(withTitles:workspaceCandidates.map(\.label)); pick.selectItem(at:min(i,workspaceCandidates.count-1)); pick.setAccessibilityLabel("位置 \(i+1) 的窗口"); return pick
        }
        workspacePreview = WorkspacePreview(); workspacePreview.widthAnchor.constraint(equalToConstant:460).isActive = true; workspacePreview.heightAnchor.constraint(equalToConstant:190).isActive = true
        var rows: [NSView] = [label("选择本次一起排列的窗口",.title),label("按编号放置，只调整选中的窗口。",.note),workspacePicker,screenChoices,workspacePreview]
        for (i,pick) in workspaceChoices.enumerated() { rows.append(stack([label("\(i+1)"),pick],horizontal:true)) }
        let apply = NSButton(title:"应用工作布局",target:self,action:#selector(applyWorkspace)); Theme.style(apply,.primary)
        rows += [apply,label("窗口有最小尺寸时可能无法容纳；失败会尝试恢复，仍可从菜单撤销。\n需要新增窗口时，关闭此面板后重新打开以刷新列表。")]
        workspacePanel?.close(); workspacePanel = panel(title:"轻分屏 · 工作布局",width:540,height:650,content:stack(rows)); workspaceChanged(); present(workspacePanel)
    }
    @objc func workspaceChanged() {
        let selected = Workspace.allCases[max(0,workspacePicker.indexOfSelectedItem)]
        workspacePreview.workspace = selected
        workspacePreview.setAccessibilityElement(true); workspacePreview.setAccessibilityRole(.image)
        workspacePreview.setAccessibilityLabel("布局预览：\(selected.title)，共 \(selected.units.count) 个窗口位置")
        for (i,choice) in workspaceChoices.enumerated() { choice.isEnabled = i < selected.units.count }
    }
    @objc func applyWorkspace() {
        guard !paused else { report("轻分屏已暂停。请在菜单栏继续管理窗口。"); return }
        if autoWanted { setAutomatic(false) }
        let spec = Workspace.allCases[max(0,workspacePicker.indexOfSelectedItem)]
        let indexes = workspaceChoices.prefix(spec.units.count).map(\.indexOfSelectedItem)
        guard Set(indexes).count == indexes.count, indexes.allSatisfy({workspaceCandidates.indices.contains($0)}), workspaceScreens.indices.contains(screenChoices.indexOfSelectedItem) else { report("请为每个编号选择不同的窗口。"); return }
        let displayID = workspaceScreens[screenChoices.indexOfSelectedItem].id
        guard let display = engine.displays.first(where:{$0.id == displayID}) else { report("这台显示器已断开，请重新打开工作布局。"); return }
        let plan = zip(indexes,spec.units).map { (workspaceCandidates[$0.0],Geometry.tile($0.1,on:display,gap:engine.gap)) }
        do { let result = try engine.apply(plan); workspacePanel?.orderOut(nil); report(result,alert:false) } catch { report(error.localizedDescription) }
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
if CommandLine.arguments.contains("--diagnose") {
    print("trusted=\(delegate.engine.trusted) displays=\(delegate.engine.displays.count) arch=arm64")
    exit(0)
}
application.run()
