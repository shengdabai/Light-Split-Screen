import Foundation
import CoreGraphics

// Seeded randomized layout properties. SplitMix64 makes every run reproducible; a failure prints the display index and
// geometry so the case can be replayed. Compiled with Layout.swift and AutoLayout.swift only (pure policy, no AppKit).
struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func int(_ range: ClosedRange<Int>) -> Int { range.lowerBound + Int(next() % UInt64(range.count)) }
    // Multiples of 0.5, so half-point sizes and origins are covered.
    mutating func half(_ range: ClosedRange<Int>) -> CGFloat { CGFloat(int(range.lowerBound * 2...range.upperBound * 2)) / 2 }
}

@main enum Tests {
    static let seed: UInt64 = 0x51F0_2026_1023
    static let displayCount = 4000
    // Device-pixel rounding on a 1x display with a half-point edge moves a frame by at most 0.5 pt.
    static let tolerance: CGFloat = 0.51

    static func randomDisplay(_ g: inout SplitMix64, id: UInt32) -> Display {
        let width = g.half(800...5120), height = g.half(500...2160)
        let x = g.half(-8000...8000), y = g.half(-4000...4000)
        let top = g.half(0...40), bottom = g.half(0...80), side = g.half(0...80)
        return Display(id: id, full: CGRect(x: x, y: y, width: width, height: height),
                       visible: CGRect(x: x + side, y: y + top, width: width - side, height: height - top - bottom),
                       scale: g.int(1...2) == 1 ? 1 : 2)
    }

    static func main() {
        var count = 0
        var context = "setup"
        func check(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String) {
            count += 1
            if !condition() { fputs("FAIL: \(message()) [\(context)]\n", stderr); exit(1) }
        }
        func inside(_ r: CGRect, _ area: CGRect) -> Bool { area.insetBy(dx: -tolerance, dy: -tolerance).contains(r) }
        // Even at gap 0, neighbouring tiles must share a device-pixel boundary without overlapping.
        func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
            let i = a.intersection(b)
            return !i.isNull && i.width > 1e-6 && i.height > 1e-6
        }

        var reference = SplitMix64(state: 0)
        check(reference.next() == 0xE220A8397B1DCDAF, "SplitMix64 first reference value")
        check(reference.next() == 0x6E789E6AA1B965F4, "SplitMix64 second reference value")
        check(reference.next() == 0x06C45D188009454F, "SplitMix64 third reference value")

        // Manual layouts whose unit rectangles do not intersect must also produce non-overlapping frames.
        let tiled = Layout.allCases.filter { $0 != .center }
        var disjointPairs: [(Layout, Layout)] = []
        for (i, a) in tiled.enumerated() {
            for b in tiled[(i + 1)...] where Geometry.area(a.unit.intersection(b.unit)) < 1e-9 { disjointPairs.append((a, b)) }
        }
        check(Layout.allCases.count == 15, "15 manual layouts")
        check(disjointPairs.count >= 20, "disjoint manual layout pairs found")

        var generator = SplitMix64(state: seed)
        for index in 0..<displayCount {
            let display = randomDisplay(&generator, id: UInt32(index + 1))
            let area = display.visible
            let aspect = area.width / area.height
            let gaps: [CGFloat] = [0, 32, CGFloat(generator.int(0...32))]
            for gap in gaps {
                context = "display #\(index) seed \(String(seed, radix: 16)) full=\(display.full) visible=\(area) scale=\(display.scale) gap=\(gap)"

                // Automatic layout: 1 to 12 windows fill the usable area without overlap.
                for n in 1...AutoLayout.maximumWindows {
                    let frames = AutoLayout.units(count: n, aspect: aspect).map { Geometry.tile($0, on: display, gap: gap) }
                    check(frames.count == n, "auto layout returns \(n) frames")
                    for (i, frame) in frames.enumerated() {
                        check(inside(frame, area), "auto layout \(n) windows: frame \(i) \(frame) outside usable area")
                        check(frame.width > 0 && frame.height > 0, "auto layout \(n) windows: frame \(i) \(frame) has non-positive size")
                        for j in frames.indices where j > i {
                            check(!overlaps(frame, frames[j]), "auto layout \(n) windows: frames \(i) and \(j) overlap")
                        }
                    }
                }

                // Manual layouts: the current window may be small, as large as the screen, or larger than the screen.
                for layout in Layout.allCases {
                    for mode in 0..<3 {
                        let scaleX: CGFloat, scaleY: CGFloat
                        switch mode {
                        case 0: scaleX = CGFloat(generator.int(10...100)) / 100; scaleY = CGFloat(generator.int(10...100)) / 100
                        case 1: scaleX = 1; scaleY = 1
                        default: scaleX = CGFloat(generator.int(101...200)) / 100; scaleY = CGFloat(generator.int(101...200)) / 100
                        }
                        let current = CGRect(x: area.minX + generator.half(-500...500), y: area.minY + generator.half(-500...500),
                                             width: (area.width * scaleX).rounded(), height: (area.height * scaleY).rounded())
                        let r = Geometry.target(layout, current: current, on: display, gap: gap)
                        check(inside(r, area), "\(layout) with current \(current) -> \(r) outside usable area")
                        check(r.width > 0 && r.height > 0, "\(layout) with current \(current) -> \(r) has non-positive size")
                        if layout == .center {
                            check(area.contains(r), "center stays strictly inside fractional visible bounds: \(current) -> \(r)")
                            check(r.width == min(current.width, area.width) && r.height == min(current.height, area.height), "center keeps size, clamped to the screen: \(current) -> \(r)")
                        } else {
                            check(r == Geometry.tile(layout.unit, on: display, gap: gap), "\(layout) ignores the current window frame")
                        }
                    }
                }
                for (a, b) in disjointPairs {
                    let fa = Geometry.target(a, current: area, on: display, gap: gap), fb = Geometry.target(b, current: area, on: display, gap: gap)
                    check(!overlaps(fa, fb), "manual layouts \(a) and \(b) overlap: \(fa) \(fb)")
                }
            }
        }
        // Transfers must remain inside the destination after proportional scaling
        // and rounding, including negative origins and fractional visible bounds.
        var transfers = SplitMix64(state: seed ^ 0x5452_414E_5346_4552)
        for index in 0..<displayCount {
            let source = randomDisplay(&transfers, id: 1)
            let destination = randomDisplay(&transfers, id: 2)
            let a = source.visible, b = destination.visible
            let width = transfers.half(1...6000), height = transfers.half(1...4000)
            let rect = CGRect(x: a.maxX-width, y: a.maxY-height, width: width, height: height)
            context = "transfer #\(index) source=\(a) destination=\(b) window=\(rect)"
            let moved = Geometry.transferred(rect, from: source, to: destination)
            check(b.contains(moved), "transferred frame \(moved) fits destination")
            check(moved.width > 0 && moved.height > 0, "transferred frame has positive size")
            check(abs(moved.width-min(b.width,max(1,width/a.width*b.width))) <= 0.5 &&
                  abs(moved.height-min(b.height,max(1,height/a.height*b.height))) <= 0.5,
                  "transferred frame keeps proportional size within rounding tolerance")
        }
        print("PASS \(count) property assertions")
    }
}
