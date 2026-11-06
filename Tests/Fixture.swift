import AppKit
final class FixtureDelegate: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []
    var floating: NSPanel?
    func makeWindow(_ index: Int) -> NSWindow {
        let w=NSWindow(contentRect:NSRect(x:160+index*70,y:200+index*60,width:650,height:450),styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
        w.title="轻分屏验收窗口 \(index+1)";w.minSize=NSSize(width:220,height:180);w.isReleasedWhenClosed=false
        let label=NSTextField(labelWithString:"仅用于轻分屏测试 · 窗口 \(index+1)\n没有用户资料，测试后可直接关闭。")
        label.frame=NSRect(x:30,y:200,width:500,height:70);label.font = .systemFont(ofSize:22);label.maximumNumberOfLines=2
        w.contentView?.addSubview(label);w.makeKeyAndOrderFront(nil);windows.append(w);return w
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let staged=CommandLine.arguments.contains("--staged-auto")
        for i in 0..<(staged ? 2 : 4) { _ = makeWindow(i) }
        if staged {
            DispatchQueue.main.asyncAfter(deadline:.now()+3) { _ = self.makeWindow(2) }
            DispatchQueue.main.asyncAfter(deadline:.now()+6) { self.windows[2].close() }
            DispatchQueue.main.asyncAfter(deadline:.now()+9) { self.windows[1].miniaturize(nil) }
            DispatchQueue.main.asyncAfter(deadline:.now()+12) { self.windows[1].deminiaturize(nil) }
            DispatchQueue.main.asyncAfter(deadline:.now()+15) { _ = self.makeWindow(3) }
        } else {
            let panel=NSPanel(contentRect:NSRect(x:1200,y:350,width:300,height:200),styleMask:[.titled,.closable,.resizable,.utilityWindow],backing:.buffered,defer:false)
            panel.title="轻分屏浮动面板验收";panel.isFloatingPanel=true;panel.isReleasedWhenClosed=false;panel.orderFront(nil);floating=panel
        }
        NSApp.activate(ignoringOtherApps:true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let app=NSApplication.shared
let delegate=FixtureDelegate();app.delegate=delegate;app.run()
