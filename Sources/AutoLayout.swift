import Foundation
import CoreGraphics

// Pure layout policy. Coordinates are normalized, top-left, in stable window order.
enum AutoLayout {
    static let maximumWindows = 12
    static func units(count: Int, aspect: CGFloat) -> [CGRect] {
        guard (1...maximumWindows).contains(count) else { return [] }
        if count == 1 { return [CGRect(x:0,y:0,width:1,height:1)] }
        if count == 2 { return aspect < 0.9 ? [Layout.top.unit,Layout.bottom.unit] : [Layout.left.unit,Layout.right.unit] }
        if count == 3 {
            if aspect >= 2.1 { return Workspace.columns.units }
            if aspect < 0.9 { return (0..<3).map { CGRect(x:0,y:CGFloat($0)/3,width:1,height:1.0/3) } }
            return [CGRect(x:0,y:0,width:0.6,height:1),CGRect(x:0.6,y:0,width:0.4,height:0.5),CGRect(x:0.6,y:0.5,width:0.4,height:0.5)]
        }
        // Fill the final row instead of leaving an unused hole.
        let columns = aspect < 0.9 ? 2 : count <= 4 ? 2 : count <= 9 ? 3 : 4
        let rows = Int(ceil(Double(count)/Double(columns)))
        return (0..<count).map { i in
            let row=i/columns, col=i%columns
            let inRow = min(columns,count-row*columns)
            return CGRect(x:CGFloat(col)/CGFloat(inRow),y:CGFloat(row)/CGFloat(rows),width:1/CGFloat(inRow),height:1/CGFloat(rows))
        }
    }
    static func stableOrder<T>(_ incoming: [T], previous: [T], same: (T,T)->Bool) -> [T] {
        let surviving = previous.compactMap { old in incoming.first(where:{same(old,$0)}) }
        return surviving + incoming.filter { new in !surviving.contains(where:{same(new,$0)}) }
    }
}

struct AutoRetryBudget {
    private var key=""
    private var attempts=0
    func permitsAttempt(for signature: String) -> Bool { key != signature || attempts < 3 }
    mutating func retry(afterFailureFor signature: String) -> Bool {
        if key != signature { key=signature;attempts=0 }
        attempts+=1
        return attempts < 3
    }
    mutating func reset() { key="";attempts=0 }
}
