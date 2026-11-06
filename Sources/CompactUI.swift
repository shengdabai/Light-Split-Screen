import AppKit

extension NSBox {
    static func separator() -> NSBox { let box=NSBox();box.boxType = .separator;return box }
}

extension NSImage {
    static func qfpMark(template: Bool = true) -> NSImage {
        let image=NSImage(size:NSSize(width:20,height:20),flipped:false) { _ in
            (template ? NSColor.black : Theme.action).setFill()
            for rect in [NSRect(x:2,y:11,width:7,height:7),NSRect(x:11,y:5,width:7,height:13),NSRect(x:2,y:2,width:8,height:7)] {
                NSBezierPath(roundedRect:rect,xRadius:1.5,yRadius:1.5).fill()
            }
            let tail=NSBezierPath();tail.move(to:NSPoint(x:9,y:5));tail.line(to:NSPoint(x:16,y:1));tail.lineWidth=2.4
            (template ? NSColor.black : Theme.action).setStroke();tail.stroke();return true
        }
        image.isTemplate=template;image.accessibilityDescription="轻分屏";return image
    }
}

final class AutoPreview: NSView {
    var units: [CGRect]=[] { didSet { needsDisplay=true } }
    override func draw(_ dirtyRect: NSRect) {
        let area=bounds.insetBy(dx:1,dy:1)
        Theme.previewCanvas.setFill();NSBezierPath(roundedRect:area,xRadius:6,yRadius:6).fill()
        Theme.border.setStroke();let outline=NSBezierPath(roundedRect:area,xRadius:6,yRadius:6);outline.lineWidth=0.7;outline.stroke()
        let content=area.insetBy(dx:9,dy:9)
        for (i,u) in units.enumerated() {
            let r=NSRect(x:content.minX+u.minX*content.width+2,y:content.minY+(1-u.maxY)*content.height+2,width:u.width*content.width-4,height:u.height*content.height-4)
            (i == 0 ? Theme.selected : Theme.card).setFill();let tile=NSBezierPath(roundedRect:r,xRadius:3,yRadius:3);tile.fill()
            Theme.action.withAlphaComponent(i == 0 ? 0.6 : 0.22).setStroke();tile.lineWidth=0.8;tile.stroke()
            if r.width > 26 && r.height > 24 {
                Theme.action.withAlphaComponent(0.65).setFill()
                NSBezierPath(roundedRect:NSRect(x:r.minX+6,y:r.maxY-10,width:min(20,r.width-12),height:3),xRadius:1,yRadius:1).fill()
            }
        }
        if units.isEmpty {
            let text=NSString(string:"等待打开窗口")
            let attrs: [NSAttributedString.Key:Any]=[.font:Theme.noteFont,.foregroundColor:Theme.muted]
            let size=text.size(withAttributes:attrs)
            text.draw(at:NSPoint(x:area.midX-size.width/2,y:area.midY-size.height/2),withAttributes:attrs)
        }
    }
}

final class DashboardController: NSViewController {
    let preview=AutoPreview()
    let message=NSTextField(wrappingLabelWithString:"")
    let subtitle=NSTextField(labelWithString:"")
    let toggle=NSSwitch()
    let primary=NSButton(title:"立即整理",target:nil,action:nil)
    let undo=NSButton(title:"撤销并暂停",target:nil,action:nil)
    let more=NSButton(title:"手动调整",target:nil,action:nil)
    let settings=NSButton(image:NSImage(systemSymbolName:"gearshape",accessibilityDescription:"设置")!,target:nil,action:nil)
    override func loadView() {
        let root=NSView(frame:NSRect(x:0,y:0,width:336,height:316));root.wantsLayer=true;root.layer?.backgroundColor=Theme.canvas.cgColor
        let icon=NSImageView();icon.image=NSImage(named:NSImage.applicationIconName) ?? .qfpMark(template:false)
        icon.imageScaling = .scaleProportionallyUpOrDown;icon.widthAnchor.constraint(equalToConstant:28).isActive=true;icon.heightAnchor.constraint(equalToConstant:28).isActive=true
        let title=NSTextField(labelWithString:"轻分屏");title.font=Theme.sectionFont;title.textColor=Theme.text
        subtitle.font=Theme.noteFont;subtitle.textColor=Theme.muted
        let names=NSStackView(views:[title,subtitle]);names.orientation = .vertical;names.alignment = .leading;names.spacing=2
        toggle.controlSize = .small;toggle.setAccessibilityLabel("持续自动分屏")
        let spacer=NSView();spacer.setContentHuggingPriority(.defaultLow,for:.horizontal)
        let header=NSStackView(views:[icon,names,spacer,toggle]);header.orientation = .horizontal;header.spacing=9;header.alignment = .centerY
        let separator=NSBox();separator.boxType = .separator
        preview.heightAnchor.constraint(equalToConstant:106).isActive=true;preview.setAccessibilityElement(true);preview.setAccessibilityRole(.image)
        message.font=Theme.noteFont;message.textColor=Theme.muted;message.maximumNumberOfLines=2;message.preferredMaxLayoutWidth=304
        message.heightAnchor.constraint(equalToConstant:32).isActive=true
        Theme.style(primary,.primary);primary.keyEquivalent="\r";primary.heightAnchor.constraint(equalToConstant:29).isActive=true
        for button in [undo,more] { button.bezelStyle = .inline;button.font=Theme.noteFont;button.contentTintColor=Theme.muted }
        settings.isBordered=false;settings.contentTintColor=Theme.muted;settings.controlSize = .small;settings.setAccessibilityLabel("轻分屏设置")
        let filler=NSView();filler.setContentHuggingPriority(.defaultLow,for:.horizontal)
        let footer=NSStackView(views:[undo,more,filler,settings]);footer.orientation = .horizontal;footer.spacing=10;footer.alignment = .centerY
        let stack=NSStackView(views:[header,separator,preview,message,primary,footer]);stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=10;stack.translatesAutoresizingMaskIntoConstraints=false
        root.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-16),stack.topAnchor.constraint(equalTo:root.topAnchor,constant:14),stack.bottomAnchor.constraint(lessThanOrEqualTo:root.bottomAnchor,constant:-12)])
        for v in [header,separator,preview,message,primary,footer] { v.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true }
        view=root
    }
    func update(_ state: AutoArrange.State, trusted: Bool, canUndo: Bool) {
        _ = view;toggle.state=state.enabled ? .on : .off
        subtitle.stringValue=trusted ? (state.enabled ? "\(state.count) 个窗口 · 持续自动" : "自动分屏已关闭") : "等待设备控制权限"
        message.stringValue=state.message;message.toolTip=state.message
        preview.units=state.preview.isEmpty ? AutoLayout.units(count:3,aspect:1.6) : state.preview
        preview.setAccessibilityLabel(state.count > 0 ? "自动布局预览，\(state.count) 个窗口" : "自动布局示意，等待窗口与权限")
        primary.title=trusted ? (state.enabled ? "立即整理" : "开启自动分屏") : "设置设备控制权限"
        undo.isEnabled=canUndo
    }
}
