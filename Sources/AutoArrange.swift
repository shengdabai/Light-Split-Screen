import AppKit
import ApplicationServices

final class AutoArrange {
    struct State {
        var enabled = true
        var count = 0
        var message = "自动整理当前桌面的窗口"
        var preview: [CGRect] = []
    }
    private struct Visible {
        let id: UInt32
        let pid: pid_t
        let frame: CGRect
        let displayID: UInt32
    }
    private struct Observation { let observer: AXObserver; let root: AXUIElement; let launchDate: Date?; var rootRegistrationSettled: Bool; var rootAttempts: Int; var nextRootAttempt: TimeInterval; var watched: [AXUIElement] }
    let engine: WindowEngine
    var onChange: ((State)->Void)?
    private(set) var state = State()
    private var enabled = false
    var isMonitoring: Bool { monitoringStarted }
    private var monitoringStarted=false
    private var timer: Timer?
    private var pending: DispatchWorkItem?
    private var notifications: [NSObjectProtocol] = []
    private var observations: [pid_t:Observation] = [:]
    private var previous: [UInt32:[WindowHandle]] = [:]
    private var orderHistory: [UInt32:[WindowHandle]] = [:]
    private var retryBudget=AutoRetryBudget()
    private var layoutRetryBudget=AutoRetryBudget()
    private var layoutFailureMessage=""
    private var fingerprint = ""
    private var displayFingerprint = ""
    private var applying = false
    private var forceLayout = false
    private let scopePID: pid_t?
    private let scopeStart: String?
    init(engine: WindowEngine, scopePID: pid_t? = nil) {
        self.engine=engine;self.scopePID=scopePID
        self.scopeStart=scopePID.flatMap(Self.processStart)
    }
    // NSRunningApplication.launchDate can be nil for a directly launched test
    // executable. The kernel start time still binds this scope to that process.
    private static func processStart(_ pid: pid_t) -> String? {
        var info=kinfo_proc(),length=MemoryLayout<kinfo_proc>.size
        var mib:[Int32]=[CTL_KERN,KERN_PROC,KERN_PROC_PID,pid]
        let result=mib.withUnsafeMutableBufferPointer { sysctl($0.baseAddress,4,&info,&length,nil,0) }
        guard result == 0,length == MemoryLayout<kinfo_proc>.size else { return nil }
        return "\(info.kp_proc.p_starttime.tv_sec):\(info.kp_proc.p_starttime.tv_usec)"
    }
    func setEnabled(_ value: Bool) {
        // Rechecking permissions/settings must not restart an active session.
        if value && enabled && monitoringStarted { return }
        stop(); enabled=value; state.enabled=value
        guard value else { state.count=0;state.preview=[];state.message="自动分屏已关闭，不会自动移动窗口"; emit(); return }
        guard engine.trusted else {
            state.message="等待设备控制权限";emit()
            timer=Timer.scheduledTimer(withTimeInterval:2,repeats:true) { [weak self] _ in
                guard let self=self,self.enabled,self.engine.trusted else { return };self.setEnabled(true)
            }
            return
        }
        if let scopePID = scopePID, NSRunningApplication(processIdentifier:scopePID)?.bundleIdentifier != "local.tony.qingfenping.fixture" {
            enabled=false;state.enabled=false;state.message="测试窗口不可用";emit();return
        }
        let nc=NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,NSWorkspace.didTerminateApplicationNotification,NSWorkspace.didHideApplicationNotification,NSWorkspace.didUnhideApplicationNotification,NSWorkspace.activeSpaceDidChangeNotification] {
            notifications.append(nc.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in self?.request() })
        }
        notifications.append(NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main) { [weak self] _ in self?.request() })
        // Check metadata when idle; retry incomplete cold-start notification registration too.
        monitoringStarted=true
        timer=Timer.scheduledTimer(withTimeInterval:3,repeats:true) { [weak self] _ in
            guard let self=self,self.pending == nil else { return }
            if self.observations.values.contains(where:{!$0.rootRegistrationSettled && ProcessInfo.processInfo.systemUptime >= $0.nextRootAttempt}) { self.fingerprint="" }
            self.request(delay:0.1)
        }
        fingerprint=""; displayFingerprint=""; forceLayout=true;retryBudget.reset();layoutRetryBudget.reset();layoutFailureMessage=""; request(delay:0.4)
    }
    func refresh() { fingerprint="";forceLayout=true;retryBudget.reset();layoutRetryBudget.reset();layoutFailureMessage="";request(delay:0.1) }
    private func windowCreated() {
        // New AX evidence may make discovery ready, but must not rearm a failed layout.
        fingerprint="";forceLayout=true;retryBudget.reset();request()
    }
    private func emit() { onChange?(state) }
    private func request(delay: TimeInterval = 0.55) {
        guard enabled else { return }
        pending?.cancel()
        let job=DispatchWorkItem { [weak self] in self?.pending=nil;self?.update() };pending=job
        DispatchQueue.main.asyncAfter(deadline:.now()+delay,execute:job)
    }
    private func visible() -> [Visible] {
        guard let list=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] else { return [] }
        let displays=engine.displays
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let pid=(info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  pid != ProcessInfo.processInfo.processIdentifier,
                  scopePID == nil || scopePID == pid,
                  let app=NSRunningApplication(processIdentifier:pid),app.activationPolicy == .regular,!app.isHidden,
                  app.bundleIdentifier != "com.apple.systempreferences",!engine.excluded.contains(app.bundleIdentifier ?? ""),
                  ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0,
                  let bounds=info[kCGWindowBounds as String] as? [String:Any], let rect=CGRect(dictionaryRepresentation:bounds as CFDictionary),
                  rect.width > 100,rect.height > 80,
                  let d=Geometry.display(for:rect,among:displays),Geometry.area(rect.intersection(d.full)) > 0,
                  let id=(info[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { return nil }
            return Visible(id:id,pid:pid,frame:rect,displayID:d.id)
        }
    }
    private func handles(for visible: [Visible]) -> (windows: [UInt32:[WindowHandle]], unresolved: Int) {
        var result: [UInt32:[WindowHandle]] = [:]
        var byPID: [pid_t:[WindowHandle]] = [:]
        var ignored: [pid_t:[CGRect]] = [:]
        for pid in Set(visible.map(\.pid)) {
            guard let app=NSRunningApplication(processIdentifier:pid) else { continue }
            let root=AXUIElementCreateApplication(pid);AXUIElementSetMessagingTimeout(root,0.15)
            guard let list=engine.attribute(root,kAXWindowsAttribute) as? [AnyObject] else { continue }
            byPID[pid]=list.prefix(40).compactMap { raw in
                guard let ax=engine.element(raw) else { return nil }
                AXUIElementSetMessagingTimeout(ax,0.15)
                let role=engine.attribute(ax,kAXSubroleAttribute) as? String
                let w=WindowHandle(ax,app:app,title:"")
                if let role=role,role != kAXStandardWindowSubrole {
                    if let frame=engine.frame(w) { ignored[pid,default:[]].append(frame) };return nil
                }
                guard role == kAXStandardWindowSubrole else { return nil }
                if (try? engine.validate(w)) != nil { return w }
                // Ignore an explicitly unsupported window; keep transient AX errors unresolved.
                var movable=DarwinBoolean(false),resizable=DarwinBoolean(false)
                let position=AXUIElementIsAttributeSettable(ax,kAXPositionAttribute as CFString,&movable)
                let size=AXUIElementIsAttributeSettable(ax,kAXSizeAttribute as CFString,&resizable)
                let knownUnsupported=(position == .success && size == .success && (!movable.boolValue || !resizable.boolValue)) ||
                    (engine.attribute(ax,kAXMinimizedAttribute) as? Bool) == true || (engine.attribute(ax,"AXFullScreen") as? Bool) == true
                if knownUnsupported,let frame=engine.frame(w) { ignored[pid,default:[]].append(frame) }
                return nil
            }
        }
        var used: [WindowHandle] = [];var unresolved=0
        for item in visible {
            let matches=(byPID[item.pid] ?? []).filter { candidate in
                !used.contains(where:{$0.same(as:candidate)}) && engine.frame(candidate).map { Geometry.near($0,item.frame,tolerance:8) } == true
            }
            // Same-position windows from another Space are ambiguous: skip, never guess.
            guard matches.count == 1,let w=matches.first else {
                if matches.isEmpty && (ignored[item.pid] ?? []).contains(where:{Geometry.near($0,item.frame,tolerance:8)}) { continue }
                unresolved+=1;continue
            }
            result[item.displayID,default:[]].append(w);used.append(w)
        }
        return (result,unresolved)
    }
    private func retry(_ key: String, message: String) -> Bool {
        guard retryBudget.retry(afterFailureFor:key) else { return false }
        state.message=message;emit();forceLayout=true;request(delay:0.8);return true
    }
    private func commit(_ next: [UInt32:[WindowHandle]], signature: String, displaySignature: String, fullyDiscovered: Bool) {
        previous=next;fingerprint=signature;displayFingerprint=displaySignature
        lastAppliedDisplaySignature=displaySignature;retryBudget.reset()
        if fullyDiscovered { layoutRetryBudget.reset();layoutFailureMessage="" }
        for (id,windows) in next {
            var history=orderHistory[id] ?? []
            for w in windows where !history.contains(where:{$0.same(as:w)}) { history.append(w) }
            orderHistory[id]=Array(history.suffix(80))
        }
        if orderHistory.count > 8 {
            for id in Array(orderHistory.keys) where next[id] == nil { orderHistory.removeValue(forKey:id) }
        }
    }
    private func update() {
        guard enabled,!applying else { return }
        if let scopePID=scopePID {
            guard let app=NSRunningApplication(processIdentifier:scopePID),app.bundleIdentifier == "local.tony.qingfenping.fixture" else {
                setEnabled(false);state.message="专用测试进程已结束";emit();return
            }
            guard let expected=scopeStart,Self.processStart(scopePID) == expected else {
                setEnabled(false);state.message="专用测试进程已结束或替换";emit();return
            }
        }
        guard engine.trusted else { state.message="设备控制权限尚未生效";emit();return }
        if NSEvent.pressedMouseButtons != 0 { request(delay:0.4);return }
        let items=visible(),displays=engine.displays
        let signature=items.map { "\($0.pid):\($0.id):\($0.displayID)" }.sorted().joined(separator:"|")
        let displaySignature=displays.map { "\($0.id):\($0.visible)" }.joined(separator:"|")
        guard signature != fingerprint || displaySignature != displayFingerprint else { return }
        let key=signature+"#"+displaySignature
        let force=forceLayout;forceLayout=false
        let discovery=handles(for:items)
        updateObservers(windows:discovery.windows.values.flatMap{$0},candidatePIDs:Set(items.map(\.pid)))
        if discovery.unresolved > 0 && retry(key,message:"等待新窗口就绪…") { return }
        state.preview=[]
        var next: [UInt32:[WindowHandle]] = [:],plan: [(WindowHandle,CGRect)] = []
        var total=0,layoutParts:[String]=[],skippedWrites=false
        for d in displays {
            let ordered=AutoLayout.stableOrder(discovery.windows[d.id] ?? [],previous:orderHistory[d.id] ?? [],same:{$0.same(as:$1)})
            next[d.id]=ordered;total+=ordered.count
            guard ordered.count <= AutoLayout.maximumWindows else {
                fingerprint=signature;displayFingerprint=displaySignature;state.count=total;state.message="单屏窗口超过12个，请最小化部分窗口";emit();return
            }
            let sameMembers=ordered.count == (previous[d.id]?.count ?? 0) && zip(ordered,previous[d.id] ?? []).allSatisfy { pair in pair.0.same(as:pair.1) }
            let units=AutoLayout.units(count:ordered.count,aspect:d.visible.width/d.visible.height)
            if !units.isEmpty && (state.preview.isEmpty || d.full.contains(CGPoint(x:NSEvent.mouseLocation.x,y:engine.desktopTop-NSEvent.mouseLocation.y))) { state.preview=units }
            let skipWrites = !force && sameMembers && state.count > 0 && displaySignature == lastAppliedDisplaySignature
            skippedWrites = skippedWrites || skipWrites
            for (window,unit) in zip(ordered,units) {
                let target=Geometry.tile(unit,on:d,gap:engine.gap)
                layoutParts.append("\(window.pid):\(CFHash(window.element)):\(target)")
                if !skipWrites && engine.frame(window).map({Geometry.accepts($0,target:target)}) != true { plan.append((window,target)) }
            }
        }
        state.count=total;updateObservers(windows:next.values.flatMap{$0})
        // A skipped no-op is not evidence that an exhausted layout became feasible.
        let layoutKey=layoutParts.sorted().joined(separator:"|")
        guard (plan.isEmpty && !skippedWrites) || layoutRetryBudget.permitsAttempt(for:layoutKey) else {
            fingerprint=signature;displayFingerprint=displaySignature
            state.message=layoutFailureMessage;emit();return
        }
        if plan.isEmpty {
            commit(next,signature:signature,displaySignature:displaySignature,fullyDiscovered:discovery.unresolved == 0)
            state.message=discovery.unresolved > 0 ? "部分窗口尚未就绪，可点立即整理重试" : total == 0 ? "等待打开普通软件窗口" : "自动分屏已开启"
            emit();return
        }
        applying=true;defer { applying=false }
        do {
            _ = try engine.apply(plan)
            commit(next,signature:signature,displaySignature:displaySignature,fullyDiscovered:discovery.unresolved == 0)
            state.message=discovery.unresolved > 0 ? "已排列可调整的窗口，其余窗口暂未就绪" : "已自动排列 \(total) 个窗口"
        } catch {
            layoutFailureMessage=error.localizedDescription + " 可点立即整理重试，或在设置中忽略该应用。"
            if layoutRetryBudget.retry(afterFailureFor:layoutKey) {
                state.message="窗口暂时繁忙，正在重试…";emit();forceLayout=true;request(delay:0.8);return
            }
            fingerprint=signature;displayFingerprint=displaySignature
            state.message=layoutFailureMessage
        }
        emit()
    }
    private var lastAppliedDisplaySignature=""
    private func updateObservers(windows: [WindowHandle], candidatePIDs: Set<pid_t> = []) {
        // Keep root/minimized-window observers until the application exits, so
        // restoring its last minimized window is detected without waiting for polling.
        let pids=Set(windows.map(\.pid)).union(observations.keys).union(candidatePIDs)
        for pid in Array(observations.keys) {
            let app=NSRunningApplication(processIdentifier:pid)
            if app == nil || app?.launchDate != observations[pid]?.launchDate { removeObserver(pid) }
        }
        for pid in pids {
            guard NSRunningApplication(processIdentifier:pid) != nil else { continue }
            if observations[pid] == nil {
                var observer: AXObserver?
                let result=AXObserverCreate(pid,{ _,_,name,context in
                    guard let context=context else { return }
                    let owner=Unmanaged<AutoArrange>.fromOpaque(context).takeUnretainedValue()
                    if name as String == kAXWindowCreatedNotification { owner.windowCreated() }
                    else { owner.request() }
                },&observer)
                guard result == .success,let observer=observer else { continue }
                let root=AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(root,0.15)
                CFRunLoopAddSource(CFRunLoopGetMain(),AXObserverGetRunLoopSource(observer),.commonModes)
                observations[pid]=Observation(observer:observer,root:root,launchDate:NSRunningApplication(processIdentifier:pid)?.launchDate,rootRegistrationSettled:false,rootAttempts:0,nextRootAttempt:0,watched:[])
            }
            guard var observation=observations[pid] else { continue }
            let now=ProcessInfo.processInfo.systemUptime
            if !observation.rootRegistrationSettled && now >= observation.nextRootAttempt {
                observation.rootAttempts+=1;observation.nextRootAttempt=now+3
                let result=AXObserverAddNotification(observation.observer,observation.root,kAXWindowCreatedNotification as CFString,Unmanaged.passUnretained(self).toOpaque())
                observation.rootRegistrationSettled = result == .success || result == .notificationAlreadyRegistered || result == .notificationUnsupported || result == .notImplemented || observation.rootAttempts >= 5
            }
            for old in observation.watched {
                for name in [kAXUIElementDestroyedNotification,kAXWindowMiniaturizedNotification,kAXWindowDeminiaturizedNotification] { AXObserverRemoveNotification(observation.observer,old,name as CFString) }
            }
            observation.watched=(engine.attribute(observation.root,kAXWindowsAttribute) as? [AnyObject] ?? []).prefix(40).compactMap { raw in
                guard let element=engine.element(raw) else { return nil }
                AXUIElementSetMessagingTimeout(element,0.15)
                guard engine.attribute(element,kAXSubroleAttribute) as? String == kAXStandardWindowSubrole else { return nil }
                return element
            }
            for window in observation.watched {
                for name in [kAXUIElementDestroyedNotification,kAXWindowMiniaturizedNotification,kAXWindowDeminiaturizedNotification] { AXObserverAddNotification(observation.observer,window,name as CFString,Unmanaged.passUnretained(self).toOpaque()) }
            }
            observations[pid]=observation
        }
    }
    private func removeObserver(_ pid: pid_t) {
        guard let observation=observations.removeValue(forKey:pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(),AXObserverGetRunLoopSource(observation.observer),.commonModes)
    }
    private func stop() {
        monitoringStarted=false
        pending?.cancel();pending=nil;timer?.invalidate();timer=nil
        for token in notifications { NSWorkspace.shared.notificationCenter.removeObserver(token);NotificationCenter.default.removeObserver(token) }
        notifications.removeAll();for pid in Array(observations.keys) { removeObserver(pid) }
    }
    deinit { stop() }
}
