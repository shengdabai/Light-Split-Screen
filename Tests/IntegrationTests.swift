import AppKit
import ApplicationServices
@main enum IntegrationTests {
    static func main() {
        _ = NSApplication.shared
        let engine = WindowEngine()
        guard engine.trusted else { print("WAITING: integration host has no Accessibility permission"); exit(3) }
        let specifiedPID = CommandLine.arguments.dropFirst().first.flatMap { Int32($0) }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier:"local.tony.qingfenping.fixture").first(where:{specifiedPID == nil || $0.processIdentifier == specifiedPID}) else { print("FAIL fixture not running"); exit(1) }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        guard let values = engine.attribute(root,kAXWindowsAttribute) as? [AXUIElement], values.count >= 2 else { print("FAIL cannot enumerate fixture windows"); exit(1) }
        let windows = values.map { engine.handle($0,app:app) }.filter { $0.title.hasPrefix("轻分屏验收窗口 ") }
        guard windows.count == 4 else { print("FAIL expected 4 owned fixture windows"); exit(1) }
        for w in windows {
            var move = DarwinBoolean(false), size = DarwinBoolean(false)
            let m = AXUIElementIsAttributeSettable(w.element,kAXPositionAttribute as CFString,&move)
            let s = AXUIElementIsAttributeSettable(w.element,kAXSizeAttribute as CFString,&size)
            print("PROBE title=\(w.title) role=\(String(describing: engine.attribute(w.element,kAXRoleAttribute))) frame=\(String(describing: engine.frame(w))) move=\(m.rawValue)/\(move.boolValue) size=\(s.rawValue)/\(size.boolValue)")
        }
        let before = windows.compactMap { engine.frame($0) }
        guard before.count == windows.count else { print("FAIL cannot read fixture frames"); exit(1) }
        var count = 0
        func check(_ pass: @autoclosure () -> Bool, _ name: String) throws {
            count += 1
            if !pass() { throw WindowFailure(message:"FAIL \(name)") }
        }
        defer { for (window,frame) in zip(windows,before) { _ = try? engine.apply([(window,frame)]) } }
        do {
            if let panel = values.map({engine.handle($0,app:app)}).first(where:{$0.title == "轻分屏浮动面板验收"}), let rect = engine.frame(panel) {
                var rejected = false
                do { try engine.validate(panel) } catch { rejected = true }
                try check(rejected,"floating panel rejected")
                let cocoa = CGPoint(x:rect.midX,y:engine.desktopTop-rect.midY)
                try check(engine.window(at:cocoa) == nil,"drag hit-test rejects floating panel")
            } else { throw WindowFailure(message:"FAIL floating panel fixture missing") }
            try engine.validate(windows[0])
            print("AX integration host trusted; fixture PID \(app.processIdentifier), displays \(engine.displays.count)")
            for display in engine.displays {
                print("DISPLAY \(display.id) full=\(display.full) visible=\(display.visible)")
                for layout in Layout.allCases {
                    let frame = Geometry.target(layout,current:before[0],on:display,gap:engine.gap)
                    print("TEST \(layout.rawValue) target=\(frame)")
                    _ = try engine.apply([(windows[0],frame)])
                    try check(Geometry.near(engine.frame(windows[0])!,frame,tolerance:4),"\(layout) display \(display.id)")
                }
            }
            if engine.displays.count > 1 {
                let destination = engine.displays.last!
                _ = try engine.apply([(windows[0],before[0])])
                _ = try engine.layout(.left,window:windows[0],displayID:destination.id)
                try check(Geometry.display(for:engine.frame(windows[0])!,among:engine.displays)?.id == destination.id,"drag explicit display wins")
            }
            _ = try engine.apply([(windows[0],before[0])])
            _ = try engine.layout(.left,window:windows[0]); _ = try engine.undo()
            try check(Geometry.near(engine.frame(windows[0])!,before[0]),"undo exact frame")
            _ = try engine.layout(.right,window:windows[0]); _ = try engine.restore(windows[0])
            let display = Geometry.display(for:before[0],among:engine.displays)!
            try check(Geometry.near(engine.frame(windows[0])!,Geometry.clamp(before[0],to:display.visible)),"restore original frame")
            if engine.displays.count > 1 {
                let prior = engine.frame(windows[0])!
                _ = try engine.transfer(windows[0],direction:1); _ = try engine.undo()
                try check(Geometry.near(engine.frame(windows[0])!,prior),"cross-display and undo")
            }
            for spec in Workspace.allCases where spec.units.count <= windows.count {
                let plan = zip(windows,spec.units).map { ($0.0,Geometry.tile($0.1,on:display,gap:8)) }
                _ = try engine.apply(plan)
                for (w,r) in plan { try check(Geometry.near(engine.frame(w)!,r,tolerance:4),"workspace \(spec.rawValue)") }
                _ = try engine.undo()
            }
            let firstBefore = engine.frame(windows[0])!, secondBefore = engine.frame(windows[1])!
            var rejected = false
            do { _ = try engine.apply([(windows[0],Geometry.tile(Layout.left.unit,on:display,gap:8)),(windows[1],CGRect(x:50,y:50,width:10,height:10))]) }
            catch { rejected = true; print("Expected impossible-size rejection: \(error.localizedDescription)") }
            try check(rejected,"minimum-size rejection")
            try check(Geometry.near(engine.frame(windows[0])!,firstBefore),"partial transaction rolls back first window")
            try check(Geometry.near(engine.frame(windows[1])!,secondBefore),"partial transaction rolls back constrained window")
            _ = try engine.apply([(windows[0],Geometry.tile(Layout.left.unit,on:display,gap:8))])
            engine.excluded = ["local.tony.qingfenping.fixture"]
            var blocked = false
            do { _ = try engine.layout(.left,window:windows[0]) } catch { blocked = true }
            try check(blocked,"excluded app rejected")
            _ = try engine.undo()
            try check(engine.canUndo,"skipped undo allows older history")
            engine.excluded = []
            let own = NSRunningApplication.current
            let invalid = WindowHandle(AXUIElementCreateApplication(own.processIdentifier),app:own,title:"")
            var ownBlocked = false
            do { try engine.validate(invalid) } catch { ownBlocked = true }
            try check(ownBlocked,"own process rejected")
            print("PASS \(count) real AX fixture assertions")
        } catch { print(error.localizedDescription); exit(1) }
    }
}
