import AppKit

// No AX reads or writes, real preferences, application enumeration, or window access.
@main enum Tests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            count += 1
            if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
        }
        let engine = WindowEngine()
        let cases: [(CGFloat, CGFloat)] = [
            (.infinity, 8), (-.infinity, 8), (.nan, 8),
            (0, 0), (8, 8), (12.5, 12.5), (32, 32), (-1, 0), (33, 32),
            (.greatestFiniteMagnitude, 32), (-.greatestFiniteMagnitude, 0)
        ]
        let area = CGRect(x: 0, y: 25, width: 1440, height: 825)
        let display = Display(id: 1, full: area, visible: area, scale: 2)
        for (input, expected) in cases {
            engine.gap = input
            check(engine.gap == expected, "gap must be finite and bounded before settings converts it to Int: \(input)")
            check(Int(engine.gap) == Int(expected), "settings can display normalized gap")
            check(Geometry.tile(Layout.left.unit, on: display, gap: input) == Geometry.tile(Layout.left.unit, on: display, gap: expected), "direct layout callers use the same gap normalization")
        }
        // A later valid edit still works after an invalid persisted value.
        engine.gap = 16
        check(engine.gap == 16, "valid gap remains editable after normalization")
        print("PASS \(count) window engine settings assertions")
    }
}
