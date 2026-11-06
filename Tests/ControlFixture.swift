import AppKit
final class Fixture:NSObject,NSApplicationDelegate {
 var windows:[NSWindow]=[]
 func add(){let i=windows.count;let w=NSWindow(contentRect:NSRect(x:100+i*90,y:120+i*60,width:500,height:320),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false);w.title="开关验收 \(i)";w.isReleasedWhenClosed=false;w.minSize=NSSize(width:220,height:180);w.makeKeyAndOrderFront(nil);windows.append(w)}
 func applicationDidFinishLaunching(_ n:Notification){add();add();NSApp.activate(ignoringOtherApps:true)
  DispatchQueue.main.asyncAfter(deadline:.now()+2){self.add()}
  DispatchQueue.main.asyncAfter(deadline:.now()+8){var f=self.windows[0].frame;f.origin.x+=40;self.windows[0].setFrame(f,display:true)}
  DispatchQueue.main.asyncAfter(deadline:.now()+10){self.add()}
 }
}
let app=NSApplication.shared;let fixture=Fixture();app.delegate=fixture;app.run()
