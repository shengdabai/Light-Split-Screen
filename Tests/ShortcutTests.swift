import AppKit
import Carbon
@main enum Tests {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            count += 1; if !condition() { fputs("FAIL \(message)\n",stderr); exit(1) }
        }
        let defaults = Shortcut.defaults
        check(defaults.count == Layout.allCases.count + 7, "all actions bound")
        for (a,first) in defaults {
            check(first.isSafe(for:a), "two safe modifiers required")
            for (b,second) in defaults where a != b { check(!first.matches(second),"unique shortcuts: \(a) \(b)") }
        }
        check(defaults["autoToggle"]?.display == "⌃S","automation switch default")
        for manual in [false,true] { for paused in [false,true] {
            let active=Shortcut.activeBindings(defaults,manualEnabled:manual,paused:paused)
            check(active["autoToggle"] == defaults["autoToggle"],"switch always reachable")
            check(active.count == (manual && !paused ? defaults.count : 1),"optional manual bindings obey off and pause")
        }}
        let controlS=Shortcut(key:1,modifiers:UInt32(controlKey),label:"S")
        check(controlS.isSafe(for:"autoToggle"),"explicit Control-S switch exception")
        check(!controlS.isSafe(for:"left"),"single modifier rejected for manual actions")
        check(Shortcut.from(event([.control],key:1),action:"autoToggle")?.key == 1,"capture Control-S for switch")
        check(Shortcut.from(event([.control],key:1),action:"left") == nil,"capture Control-S rejected for manual")
        check(Shortcut.from(event([.control],key:0),action:"autoToggle") == nil,"other single-control keys rejected")
        check(Shortcut.from(event([.command],key:1),action:"autoToggle") == nil,"Command-S not captured")
        check(Shortcut.from(event([],key:1),action:"autoToggle") == nil,"bare S never captured")
        let data = try! JSONEncoder().encode(defaults)
        check(try! JSONDecoder().decode([String:Shortcut].self,from:data) == defaults,"settings round trip")
        func event(_ flags: NSEvent.ModifierFlags, key: UInt16 = 0) -> NSEvent {
            NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:0,context:nil,characters:"a",charactersIgnoringModifiers:"a",isARepeat:false,keyCode:key)!
        }
        check(Shortcut.from(event([])) == nil,"bare key rejected")
        check(Shortcut.from(event([.option])) == nil,"option-only rejected")
        check(Shortcut.from(event([.control])) == nil,"control-only rejected")
        check(Shortcut.from(event([.control,.command]))?.modifiers == UInt32(controlKey|cmdKey),"control-command accepted")
        check(!Shortcut(key:0,modifiers:UInt32(optionKey),label:"A").isSafe,"unsafe persisted binding rejected")
        check(!Shortcut(key:0,modifiers:UInt32(controlKey|cmdKey)|0x80000000,label:"A").isSafe,"unknown persisted modifier rejected")
        check(Shortcut.from(event([.command])) == nil,"command-only rejected")
        check(Shortcut.from(event([.control,.option]))?.modifiers == UInt32(controlKey | optionKey),"control-option accepted")
        check(Shortcut.from(event([.command,.option]))?.modifiers == UInt32(cmdKey | optionKey),"command-option accepted")
        check(Shortcut.from(event([.control,.option],key:123))?.label == "←","arrow name")
        print("PASS \(count) shortcut / persistence / typing-safety assertions")
    }
}
