import Foundation
import CoreGraphics
@main enum Tests {
    static func main() {
        var checks=0
        func check(_ value: @autoclosure()->Bool,_ message: String) { checks+=1;if !value() {fputs("FAIL \(message)\n",stderr);exit(1)} }
        for aspect: CGFloat in [0.6,0.9,1.3,1.78,2.5,3.6] {
            for n in 1...12 {
                let units=AutoLayout.units(count:n,aspect:aspect)
                check(units.count==n,"correct count")
                for (i,u) in units.enumerated() {
                    check(CGRect(x:0,y:0,width:1,height:1).insetBy(dx:-0.0001,dy:-0.0001).contains(u),"within display")
                    check(u.width>0 && u.height>0,"positive size")
                    for (j,v) in units.enumerated() where i != j {check(Geometry.area(u.intersection(v)) < 0.00001,"no overlap")}
                }
                check(abs(units.map(Geometry.area).reduce(0,+)-1)<0.00001,"fill display")
            }
        }
        check(AutoLayout.units(count:0,aspect:1.6).isEmpty,"zero windows")
        check(AutoLayout.units(count:13,aspect:1.6).isEmpty,"over limit")
        check(AutoLayout.units(count:2,aspect:0.6)[0].height==0.5,"portrait stacks vertically")
        check(AutoLayout.units(count:3,aspect:2.5)==Workspace.columns.units,"ultrawide uses columns")
        // Seeded reproduction: equivalent row edges rounded to opposite sides of a half-pixel.
        for scale: CGFloat in [1, 2] {
            let portrait = Display(id: 4, full: CGRect(x: -5887.5, y: -1326.5, width: 1581, height: 2077.5),
                                   visible: CGRect(x: -5815, y: -1325, width: 1508.5, height: 2032.5), scale: scale)
            let frames = AutoLayout.units(count: 9, aspect: portrait.visible.width/portrait.visible.height)
                .map { Geometry.tile($0, on: portrait, gap: 0) }
            check(frames[4].maxY == frames[6].minY, "adjacent portrait rows share a pixel boundary at scale \(scale)")
            check(Geometry.area(frames[4].intersection(frames[6])) == 0, "portrait rows do not overlap at scale \(scale)")
        }
        check(AutoLayout.stableOrder([3,1,4,2],previous:[1,2,3],same:==)==[1,2,3,4],"focus changes don't reorder")
        check(AutoLayout.stableOrder([3,4],previous:[1,2,3],same:==)==[3,4],"closed windows removed, new appended")
        check(AutoLayout.stableOrder([8,9],previous:[1,2],same:==)==[8,9],"entire membership replaced")
        check(AutoLayout.stableOrder([2,1],previous:[1,2,7,8],same:==)==[1,2],"returning Space keeps historical order")
        var retry=AutoRetryBudget()
        check(retry.retry(afterFailureFor:"window-A"),"first transient failure retries")
        check(retry.retry(afterFailureFor:"window-A"),"second transient failure retries")
        check(!retry.retry(afterFailureFor:"window-A"),"third identical failure stops")
        check(!retry.retry(afterFailureFor:"window-A"),"does not restart same exhausted failure")
        check(retry.retry(afterFailureFor:"window-B"),"new membership gets a new budget")
        retry.reset()
        check(retry.retry(afterFailureFor:"window-A"),"explicit refresh can retry after reset")
        var writes=AutoRetryBudget()
        check(writes.permitsAttempt(for:"layout-2"),"first layout attempt allowed")
        _ = writes.retry(afterFailureFor:"layout-2")
        _ = writes.retry(afterFailureFor:"layout-2")
        check(writes.permitsAttempt(for:"layout-2"),"third layout attempt still allowed")
        _ = writes.retry(afterFailureFor:"layout-2")
        for _ in 0..<20 { check(!writes.permitsAttempt(for:"layout-2"),"external discovery cannot rearm failed layout") }
        check(writes.permitsAttempt(for:"layout-3"),"new eligible membership can attempt")
        writes.reset()
        check(writes.permitsAttempt(for:"layout-2"),"explicit manual reset can attempt")
        print("PASS \(checks) automatic layout / stable-membership assertions")
    }
}
