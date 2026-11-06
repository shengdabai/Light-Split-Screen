import Foundation
import CoreGraphics

// All layout calculations use Accessibility's global, top-left coordinate space.
enum Layout: String, CaseIterable, Codable {
    case left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight
    case firstThird, middleThird, lastThird, leftTwoThirds, rightTwoThirds, maximize, center
    var title: String {
        switch self {
        case .left: return "左半屏"; case .right: return "右半屏"
        case .top: return "上半屏"; case .bottom: return "下半屏"
        case .topLeft: return "左上角"; case .topRight: return "右上角"
        case .bottomLeft: return "左下角"; case .bottomRight: return "右下角"
        case .firstThird: return "左侧 1/3"; case .middleThird: return "中间 1/3"; case .lastThird: return "右侧 1/3"
        case .leftTwoThirds: return "左侧 2/3"; case .rightTwoThirds: return "右侧 2/3"
        case .maximize: return "最大化"; case .center: return "居中（保留尺寸）"
        }
    }
    var unit: CGRect {
        switch self {
        case .left: return CGRect(x: 0, y: 0, width: 0.5, height: 1)
        case .right: return CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        case .top: return CGRect(x: 0, y: 0, width: 1, height: 0.5)
        case .bottom: return CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        case .topLeft: return CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRight: return CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .bottomLeft: return CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .bottomRight: return CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .firstThird: return CGRect(x: 0, y: 0, width: 1.0/3, height: 1)
        case .middleThird: return CGRect(x: 1.0/3, y: 0, width: 1.0/3, height: 1)
        case .lastThird: return CGRect(x: 2.0/3, y: 0, width: 1.0/3, height: 1)
        case .leftTwoThirds: return CGRect(x: 0, y: 0, width: 2.0/3, height: 1)
        case .rightTwoThirds: return CGRect(x: 1.0/3, y: 0, width: 2.0/3, height: 1)
        case .maximize, .center: return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
    }
}

enum Workspace: String, CaseIterable {
    case compare, development, columns, grid
    var title: String {
        switch self { case .compare: return "双窗对照"; case .development: return "开发三窗"; case .columns: return "等宽三窗"; case .grid: return "四窗网格" }
    }
    var units: [CGRect] {
        switch self {
        case .compare: return [Layout.left.unit, Layout.right.unit]
        case .development: return [Layout.leftTwoThirds.unit, CGRect(x: 2.0/3, y: 0, width: 1.0/3, height: 0.5), CGRect(x: 2.0/3, y: 0.5, width: 1.0/3, height: 0.5)]
        case .columns: return [Layout.firstThird.unit, Layout.middleThird.unit, Layout.lastThird.unit]
        case .grid: return [Layout.topLeft.unit, Layout.topRight.unit, Layout.bottomLeft.unit, Layout.bottomRight.unit]
        }
    }
}

struct Display {
    let id: UInt32
    let full: CGRect
    let visible: CGRect
    let scale: CGFloat
}

enum Geometry {
    static func axRect(_ cocoa: CGRect, desktopTop: CGFloat) -> CGRect {
        CGRect(x: cocoa.minX, y: desktopTop - cocoa.maxY, width: cocoa.width, height: cocoa.height)
    }
    static func cocoaRect(_ ax: CGRect, desktopTop: CGFloat) -> CGRect { axRect(ax, desktopTop: desktopTop) }
    static func display(for rect: CGRect, among displays: [Display]) -> Display? {
        guard !displays.isEmpty else { return nil }
        let overlaps = displays.map { ($0, area(rect.intersection($0.full))) }
        if let best = overlaps.max(by: { $0.1 < $1.1 }), best.1 > 0 { return best.0 }
        return displays.min { distance(rect, $0.full) < distance(rect, $1.full) }
    }
    static func area(_ r: CGRect) -> CGFloat { r.isNull || r.isInfinite ? 0 : max(0, r.width) * max(0, r.height) }
    static func distance(_ a: CGRect, _ b: CGRect) -> CGFloat { pow(a.midX-b.midX, 2) + pow(a.midY-b.midY, 2) }
    static func normalizedGap(_ gap: CGFloat) -> CGFloat {
        gap.isFinite ? min(max(gap, 0), 32) : 8
    }
    static func tile(_ unit: CGRect, on display: Display, gap: CGFloat) -> CGRect {
        let area = display.visible
        let spacing = normalizedGap(gap)
        let x1 = (area.minX + unit.minX * area.width + spacing/2) * display.scale
        let y1 = (area.minY + unit.minY * area.height + spacing/2) * display.scale
        let x2 = (area.minX + unit.maxX * area.width - spacing/2) * display.scale
        let y2 = (area.minY + unit.maxY * area.height - spacing/2) * display.scale
        // Equivalent unit edges (such as 0.4 + 0.2 and 0.6) can straddle a half-pixel
        // because of floating-point error. Resolve those ties consistently before rounding.
        let epsilon = max(1, abs(area.minX), abs(area.minY), area.width, area.height) * display.scale * CGFloat.ulpOfOne * 8
        func pixel(_ value: CGFloat) -> CGFloat {
            let half = (value * 2).rounded() / 2
            return (abs(value - half) <= epsilon ? half : value).rounded() / display.scale
        }
        let left = pixel(x1), top = pixel(y1), right = pixel(x2), bottom = pixel(y2)
        return CGRect(x: left, y: top, width: max(1, right-left), height: max(1, bottom-top))
    }
    static func target(_ layout: Layout, current: CGRect, on display: Display, gap: CGFloat) -> CGRect {
        if layout != .center { return tile(layout.unit, on: display, gap: gap) }
        let a = display.visible
        let w = min(current.width, a.width), h = min(current.height, a.height)
        let centered = CGRect(x: (a.midX-w/2).rounded(), y: (a.midY-h/2).rounded(), width: w, height: h)
        // A full-size window on a half-point origin has no room for rounding.
        return clamp(centered, to: a)
    }
    static func transferred(_ rect: CGRect, from source: Display, to destination: Display) -> CGRect {
        let a = source.visible, b = destination.visible
        let w = min(b.width, max(1, rect.width/a.width*b.width))
        let h = min(b.height, max(1, rect.height/a.height*b.height))
        let x = b.minX + (rect.minX-a.minX)/a.width*b.width
        let y = b.minY + (rect.minY-a.minY)/a.height*b.height
        // Rounding position and size independently can add a point beyond the
        // destination edge. Clamp the final frame, after both have been rounded.
        let rounded = CGRect(x: min(max(x, b.minX), b.maxX-w).rounded(), y: min(max(y, b.minY), b.maxY-h).rounded(), width: w.rounded(), height: h.rounded())
        return clamp(rounded, to: b)
    }
    static func clamp(_ rect: CGRect, to area: CGRect) -> CGRect {
        let w = min(rect.width, area.width), h = min(rect.height, area.height)
        return CGRect(x: min(max(rect.minX, area.minX), area.maxX-w), y: min(max(rect.minY, area.minY), area.maxY-h), width: w, height: h)
    }
    static func near(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 3) -> Bool {
        abs(a.minX-b.minX) <= tolerance && abs(a.minY-b.minY) <= tolerance && abs(a.width-b.width) <= tolerance && abs(a.height-b.height) <= tolerance
    }
    static func accepts(_ actual: CGRect, target: CGRect) -> Bool {
        // Terminal-style character grids may round dimensions down by one cell.
        abs(actual.minX-target.minX) <= 4 && abs(actual.minY-target.minY) <= 4 &&
        (-4...24).contains(target.width-actual.width) && (-4...24).contains(target.height-actual.height)
    }
    static func isMove(start: CGRect, current: CGRect) -> Bool {
        abs(start.width-current.width) <= 3 && abs(start.height-current.height) <= 3 &&
        (abs(start.minX-current.minX) > 4 || abs(start.minY-current.minY) > 4)
    }
    // Pointer is AX/global top-left. Corners win; bottom edge offers thirds.
    static func snap(at p: CGPoint, display: Display, threshold: CGFloat = 22) -> Layout? {
        let r = display.full
        guard r.insetBy(dx: -1, dy: -1).contains(p) else { return nil }
        let left = p.x-r.minX <= threshold, right = r.maxX-p.x <= threshold
        let top = p.y-r.minY <= threshold, bottom = r.maxY-p.y <= threshold
        if top && left { return .topLeft }; if top && right { return .topRight }
        if bottom && left { return .bottomLeft }; if bottom && right { return .bottomRight }
        if top { return .maximize }
        if bottom {
            let t = (p.x-r.minX)/r.width
            return t < 1.0/3 ? .firstThird : t > 2.0/3 ? .lastThird : .middleThird
        }
        if left { return .left }; if right { return .right }
        return nil
    }
}
