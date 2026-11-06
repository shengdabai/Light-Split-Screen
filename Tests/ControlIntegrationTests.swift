import AppKit
import ApplicationServices
@main enum ControlIntegration {
 static func main(){
  let app=NSApplication.shared
  let domain="local.tony.qingfenping.control-test.\(UUID().uuidString)";let prefs=UserDefaults(suiteName:domain)!
  prefs.set(true,forKey:"continuousAuto");prefs.set(false,forKey:"hotkeysEnabled")
  let d=AppDelegate(defaults:prefs);app.delegate=d
  guard let pid=d.fixturePID else{exit(2)}
  var checks=0,failed=false
  func check(_ ok:Bool,_ name:String){checks+=1;print(ok ? "PASS \(name)":"FAIL \(name)");failed = failed || !ok;fflush(stdout)}
  func frames()->[String:CGRect]{
   guard let owner=NSRunningApplication(processIdentifier:pid) else{return [:]};let root=AXUIElementCreateApplication(pid);AXUIElementSetMessagingTimeout(root,0.15)
   var result:[String:CGRect]=[:]
   for raw in (d.engine.attribute(root,kAXWindowsAttribute) as? [AnyObject] ?? []) {if let ax=d.engine.element(raw){let w=d.engine.handle(ax,app:owner);if (try? d.engine.validate(w)) != nil,let f=d.engine.frame(w){result[w.title]=f}}};return result
  }
  func tiled(_ n:Int){let fs=frames();check(fs.count==n,"tiled membership \(n)");check(d.autoState.count==n,"app state membership \(n)")
   for (name,f) in fs {check(d.engine.displays.contains{ $0.visible.insetBy(dx:-4,dy:-4).contains(f)},"inside display \(name)");for (other,g) in fs where name != other {check(Geometry.area(f.intersection(g))<1,"no overlap \(name) \(other)")}}
  }
  var initial:[String:CGRect]=[:],beforeOff:[String:CGRect]=[:],afterOwnMove:[String:CGRect]=[:],emits=0
  DispatchQueue.main.asyncAfter(deadline:.now()+0.3){
   initial=frames();check(initial.count==2,"initial fixture windows")
   check(d.engine.trusted,"test host AX permission");if !d.engine.trusted{prefs.removePersistentDomain(forName:domain);exit(3)}
   check(!d.autoWanted && !prefs.bool(forKey:"continuousAuto"),"saved-on startup becomes off")
   check(!d.automatic.isMonitoring && !d.drag.enabled,"startup no auto monitor or drag snapping")
   check(d.shortcutFailures.isEmpty,"dedicated switch registered with manual shortcuts off")
  }
  DispatchQueue.main.asyncAfter(deadline:.now()+3.2){let fs=frames();check(fs.count==3,"off observes fixture-created third window read-only");check(initial.allSatisfy{fs[$0.key]==$0.value} && fs["开关验收 2"]?.width==500,"startup and open events preserve original sizes");d.run("autoToggle",fresh:true)}
  DispatchQueue.main.asyncAfter(deadline:.now()+6){tiled(3);let original=d.automatic.onChange;d.automatic.onChange={state in emits+=1;original?(state)};d.setAutomatic(true)}
  DispatchQueue.main.asyncAfter(deadline:.now()+6.5){check(emits==0,"repeated enable does not restart coordinator");beforeOff=frames();d.automatic.refresh();d.run("autoToggle",fresh:true);check(!d.autoWanted && !d.automatic.isMonitoring && !d.drag.enabled,"toggle off stops all automatic paths")}
  DispatchQueue.main.asyncAfter(deadline:.now()+7.2){check(frames()==beforeOff,"off cancels queued refresh without rollback")}
  DispatchQueue.main.asyncAfter(deadline:.now()+8.6){afterOwnMove=frames();check(afterOwnMove != beforeOff,"fixture moved own window while off")}
  DispatchQueue.main.asyncAfter(deadline:.now()+12){let fs=frames();check(fs.count==4,"new window exists while off");check(afterOwnMove.allSatisfy{fs[$0.key]==$0.value},"off preserves user positions across new-window and poll events");check(fs["开关验收 3"]?.width==500,"off does not resize newly opened window");d.run("autoToggle",fresh:true)}
  DispatchQueue.main.asyncAfter(deadline:.now()+15){tiled(4);d.setAutomatic(false);check(!prefs.bool(forKey:"continuousAuto"),"off persisted");prefs.removePersistentDomain(forName:domain);print(failed ? "CONTROL_INTEGRATION_FAILED":"PASS \(checks) actual AppDelegate and real-window control assertions");fflush(stdout);exit(failed ? 1:0)}
  app.run()
 }
}
