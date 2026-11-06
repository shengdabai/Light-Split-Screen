import AppKit
import ApplicationServices
@main enum Probe {
 static func main() {
  _ = NSApplication.shared
  let e=WindowEngine()
  guard let app=NSRunningApplication.runningApplications(withBundleIdentifier:"local.tony.qingfenping.fixture").first else { exit(1) }
  let root=AXUIElementCreateApplication(app.processIdentifier)
  let all=e.attribute(root,kAXWindowsAttribute) as! [AXUIElement]
  let w=all.map {e.handle($0,app:app)}.first {$0.title.hasPrefix("轻分屏验收窗口 ")}!
  let original=e.frame(w)!
  let display=e.displays.last!
  let target=Geometry.tile(Layout.left.unit,on:display,gap:8)
  var pos=target.origin,size=target.size
  let p=AXValueCreate(.cgPoint,&pos)!,s=AXValueCreate(.cgSize,&size)!
  print("original \(original) target \(target)")
  for (key,value) in [(kAXSizeAttribute,s),(kAXPositionAttribute,p),(kAXSizeAttribute,s),(kAXPositionAttribute,p)] {
   print("SET \(key) \(AXUIElementSetAttributeValue(w.element,key as CFString,value).rawValue) actual=\(String(describing:e.frame(w)))")
  }
  for wait in [0.05,0.15,0.3] { Thread.sleep(forTimeInterval:wait); print("AFTER \(wait) resize=\(AXUIElementSetAttributeValue(w.element,kAXSizeAttribute as CFString,s).rawValue) actual=\(String(describing:e.frame(w)))") }
  _ = try? e.apply([(w,original)])
 }
}
