import Foundation
import CoreGraphics

@main enum Tests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            count += 1
            if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
        }
        let main = Display(id: 1, full: CGRect(x: 0, y: 0, width: 1440, height: 900), visible: CGRect(x: 0, y: 25, width: 1440, height: 825), scale: 2)
        let left = Display(id: 2, full: CGRect(x: -1920, y: -300, width: 1920, height: 1080), visible: CGRect(x: -1920, y: -275, width: 1920, height: 1005), scale: 1)
        let above = Display(id: 3, full: CGRect(x: 0, y: -1080, width: 1920, height: 1080), visible: CGRect(x: 0, y: -1055, width: 1920, height: 1055), scale: 1)
        for display in [main, left, above] {
            for layout in Layout.allCases {
                let r = Geometry.target(layout, current: CGRect(x: 0, y: 0, width: 700, height: 500), on: display, gap: 8)
                check(display.visible.insetBy(dx: -0.5, dy: -0.5).contains(r), "\(layout) fits screen \(display.id)")
                check(r.width > 0 && r.height > 0, "positive size")
            }
        }
        let l = Geometry.target(.left, current: .zero, on: main, gap: 8), r = Geometry.target(.right, current: .zero, on: main, gap: 8)
        check(r.minX-l.maxX == 8, "gap exactly 8")
        check(l.minY == 29 && l.maxY == 846, "menu and Dock excluded")
        let input = CGRect(x: -1600, y: 150, width: 800, height: 600)
        check(Geometry.display(for: input, among: [main, left, above])?.id == 2, "negative screen")
        check(Geometry.display(for: CGRect(x: -50, y: 50, width: 1200, height: 700), among: [main, left])?.id == 1, "largest intersection")
        check(Geometry.display(for: CGRect(x: 9000, y: 9000, width: 400, height: 300), among: [main])?.id == 1, "offscreen fallback")
        check(Geometry.display(for: input, among: []) == nil, "no screen")
        let cocoa = CGRect(x: -1920, y: 900, width: 1920, height: 1080)
        check(Geometry.cocoaRect(Geometry.axRect(cocoa, desktopTop: 900), desktopTop: 900) == cocoa, "coordinate roundtrip above primary")
        let moved = Geometry.transferred(input, from: left, to: main)
        check(main.visible.contains(moved), "transfer fits destination")
        let source = Display(id: 4, full: CGRect(x: 0, y: 0, width: 1600, height: 1000),
                             visible: CGRect(x: 0, y: 0, width: 1600, height: 1000), scale: 1)
        let destination = Display(id: 5, full: CGRect(x: 0, y: 0, width: 800, height: 500),
                                  visible: CGRect(x: 0, y: 0, width: 800, height: 500), scale: 1)
        let edgeWindow = CGRect(x: 799, y: 399, width: 801, height: 601)
        let edgeMoved = Geometry.transferred(edgeWindow, from: source, to: destination)
        check(destination.visible.contains(edgeMoved), "rounding a transferred window cannot push its right or bottom edge offscreen")
        check(edgeMoved.size == CGSize(width: 401, height: 301), "transfer keeps rounded proportional size")
        check(edgeMoved.maxX == destination.visible.maxX && edgeMoved.maxY == destination.visible.maxY, "transfer retains the destination corner")
        for origin: CGFloat in [-1000.5, 0.5, 1000.5] {
            let area = CGRect(x: origin, y: origin, width: 800, height: 500)
            let fractional = Display(id: 6, full: area, visible: area, scale: 2)
            for size in [CGSize(width: 800, height: 500), CGSize(width: 799.5, height: 499.5), CGSize(width: 1200, height: 900)] {
                let centered = Geometry.target(.center, current: CGRect(origin: .zero, size: size), on: fractional, gap: 8)
                check(area.contains(centered), "centering at fractional bounds cannot move an edge outside the display")
                check(centered.width == min(size.width, area.width) && centered.height == min(size.height, area.height), "centering retains size within display limits")
            }
        }
        check(Geometry.clamp(input, to: main.visible).minX == 0, "restore after disconnect")
        check(Geometry.isMove(start: input, current: input.offsetBy(dx: 30, dy: 0)), "move recognized")
        check(!Geometry.isMove(start: input, current: CGRect(x: -1590, y: 150, width: 790, height: 600)), "resize rejected")
        check(!Geometry.isMove(start: input, current: input), "text drag rejected")
        let target = CGRect(x:4,y:35,width:952,height:948)
        check(Geometry.accepts(CGRect(x:4,y:35,width:943,height:933),target:target),"character-grid rounding accepted")
        check(!Geometry.accepts(CGRect(x:4,y:35,width:980,height:948),target:target),"minimum-size overflow rejected")
        check(!Geometry.accepts(target.offsetBy(dx:20,dy:0),target:target),"wrong position rejected")
        check(Geometry.snap(at: CGPoint(x: 0, y: 0), display: main) == .topLeft, "corner wins")
        check(Geometry.snap(at: CGPoint(x: 720, y: 1), display: main) == .maximize, "top edge")
        check(Geometry.snap(at: CGPoint(x: 700, y: 899), display: main) == .middleThird, "bottom third")
        check(Geometry.snap(at: CGPoint(x: 700, y: 450), display: main) == nil, "center no snap")
        check(Geometry.snap(at: CGPoint(x: -1920, y: 20), display: left) == .left, "negative-coordinate edge")
        for workspace in Workspace.allCases {
            check((2...4).contains(workspace.units.count), "workspace count")
            let frames = workspace.units.map { Geometry.tile($0, on: main, gap: 8) }
            for (i,a) in frames.enumerated() {
                check(main.visible.contains(a), "workspace fits")
                for (j,b) in frames.enumerated() where i != j { check(Geometry.area(a.intersection(b)) == 0, "workspace no overlap") }
            }
        }
        print("PASS \(count) geometry / layout / drag-guard assertions")
    }
}
