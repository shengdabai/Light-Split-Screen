import AppKit
import ApplicationServices
@main enum AutoIntegration {
    static func main() {
        let app=NSApplication.shared;app.setActivationPolicy(.accessory)
        guard let value=CommandLine.arguments.dropFirst().first,let pid=Int32(value) else { exit(1) }
        let engine=WindowEngine();guard engine.trusted else { print("WAITING no AX permission for test host");exit(3) }
        let coordinator=AutoArrange(engine:engine,scopePID:pid)
        var checks=0,failed=false
        func check(_ condition:Bool,_ message:String) {
            checks+=1;if !condition { print("FAIL \(message)");failed=true } else { print("PASS \(message)") };fflush(stdout)
        }
        coordinator.onChange={ state in print("STATE enabled=\(state.enabled) count=\(state.count) message=\(state.message)");fflush(stdout) }
        coordinator.setEnabled(true)
        func verify(_ count:Int,_ label:String) {
            check(coordinator.state.count==count,"\(label) membership \(count)")
            guard let owner=NSRunningApplication(processIdentifier:pid) else { check(false,"fixture running");return }
            let root=AXUIElementCreateApplication(pid)
            let candidates=(engine.attribute(root,kAXWindowsAttribute) as? [AnyObject] ?? []).compactMap { raw -> WindowHandle? in
                guard let ax=engine.element(raw) else { return nil };let w=engine.handle(ax,app:owner)
                return (try? engine.validate(w)) == nil ? nil : w
            }
            check(candidates.count==count,"\(label) standard visible windows")
            for w in candidates {
                guard let frame=engine.frame(w),let d=Geometry.display(for:frame,among:engine.displays) else {check(false,"read frame");continue}
                check(d.visible.insetBy(dx:-4,dy:-4).contains(frame),"\(label) inside display")
                for other in candidates where !w.same(as:other) { if let b=engine.frame(other) {check(Geometry.area(frame.intersection(b))<1,"\(label) no overlap")} }
            }
        }
        // Fixture starts 0.35s before this coordinator. Checks leave >1s after AX events.
        for (seconds,count,name) in [(1.5,2,"initial"),(4.5,3,"open"),(7.5,2,"close"),(10.5,1,"minimize"),(13.5,2,"restore")] {
            DispatchQueue.main.asyncAfter(deadline:.now()+seconds) { verify(count,name) }
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+13.7) { coordinator.setEnabled(false);check(!coordinator.state.enabled,"pause stops automatic mode") }
        DispatchQueue.main.asyncAfter(deadline:.now()+17) {
            check(!coordinator.state.enabled && coordinator.state.count==0,"new window after pause does not trigger reflow")
            print(failed ? "AUTO_INTEGRATION_FAILED" : "PASS \(checks) continuous real-window assertions")
            coordinator.setEnabled(false);fflush(stdout);exit(failed ? 1 : 0)
        }
        app.run()
    }
}
