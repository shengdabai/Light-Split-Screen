import AppKit

/// 轻分屏视觉主题：固定浅色外观 + 单一蓝色品牌色。颜色均为 sRGB 常量，不随系统深色模式变化。
enum Theme {
    // MARK: Colors（括号内为相对 canvas 的对比度）
    static let canvas      = rgb(0xFAFBFD)   // 近白底色，浅蓝仅用于强调
    static let previewCanvas = rgb(0xF2F5F9)
    static let selected    = rgb(0xEAF3FD)
    static let card        = rgb(0xFFFFFF)   // 预览底、输入框
    static let border      = rgb(0xC8D0DA)
    static let text        = rgb(0x1D1D1F)
    static let muted       = rgb(0x5F6B7A)
    static let action      = rgb(0x1F6FD6)
    static let previewFill = rgb(0xCFE2F7)   // 预览格；深色编号其上 11.7:1
    static let success     = rgb(0x1C6B3A)   // 5.8:1
    static let warning     = rgb(0x8A4B00)   // 6.1:1

    // MARK: Typography
    static let titleFont   = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let sectionFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let bodyFont    = NSFont.systemFont(ofSize: 13)
    static let noteFont    = NSFont.systemFont(ofSize: 12)
    static let buttonFont  = NSFont.systemFont(ofSize: 13, weight: .medium)

    // MARK: Spacing
    static let padX: CGFloat = 20, padTop: CGFloat = 16, padBottom: CGFloat = 20
    static let rowGap: CGFloat = 8, sectionGap: CGFloat = 16
    static let radius: CGFloat = 8
    static let layoutButtonWidth: CGFloat = 148
    /// 换行宽度：面板宽减左右边距，再预留 16pt 给“始终显示”的滚动条。
    static func wrapWidth(forPanel width: CGFloat) -> CGFloat { width - 2 * padX - 16 }

    // MARK: Appearance
    static let lightAppearance = NSAppearance(named: .aqua)
    /// 用户要求浅蓝界面：整个应用（面板、NSAlert、菜单、弹出菜单）固定浅色。
    static func forceLight() { NSApp.appearance = lightAppearance }

    static func apply(to window: NSWindow) {
        window.appearance = lightAppearance
        window.backgroundColor = canvas
        window.titlebarAppearsTransparent = true
    }

    /// 通用背景辅助：图层底色 + 可选圆角与 1pt 描边。
    static func paint(_ view: NSView, _ color: NSColor, radius: CGFloat = 0, border: NSColor? = nil) {
        view.wantsLayer = true
        view.layer?.backgroundColor = color.cgColor
        view.layer?.cornerRadius = radius
        view.layer?.borderColor = border?.cgColor
        view.layer?.borderWidth = border == nil ? 0 : 1
    }

    // MARK: Text
    enum Text { case title, section, body, note, status(ok: Bool) }

    static func style(_ f: NSTextField, _ kind: Text) {
        switch kind {
        case .title:   f.font = titleFont;   f.textColor = text
        case .section: f.font = sectionFont; f.textColor = text
        case .body:    f.font = bodyFont;    f.textColor = text
        case .note:    f.font = noteFont;    f.textColor = muted
        case .status(let ok):
            f.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            f.textColor = ok ? success : warning
        }
        f.lineBreakMode = .byWordWrapping
        f.setContentCompressionResistancePriority(.required, for: .vertical)
    }

    static func style(field f: NSTextField) {
        f.font = bodyFont; f.textColor = text
        f.drawsBackground = true; f.backgroundColor = card
    }

    /// 递归处理垂直栈中的换行标签，保证在 520/540/570 宽面板中完整换行、不截断。
    static func fitLabels(in stack: NSStackView, width: CGFloat) {
        for view in stack.arrangedSubviews {
            if let f = view as? NSTextField, !f.isEditable, f.cell?.wraps == true {
                f.preferredMaxLayoutWidth = width
                f.widthAnchor.constraint(lessThanOrEqualToConstant: width).isActive = true
            } else if let s = view as? NSStackView, s.orientation == .vertical {
                fitLabels(in: s, width: width)
            }
        }
    }

    // MARK: Buttons（仍是原生 NSButton，不改焦点环与交互）
    enum Role { case primary, secondary, layout }

    static func style(_ b: NSButton, _ role: Role) {
        b.bezelStyle = .rounded
        b.controlSize = .regular
        b.font = role == .layout ? buttonFont : bodyFont
        b.bezelColor = role == .primary ? action : nil
        b.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    }

    static func style(checkbox b: NSButton) { b.font = bodyFont }

    // MARK: Previews
    /// 工作布局预览：白底 + 浅蓝格 + 居中编号。units 为 0–1 归一化矩形（y 向上）。
    static func drawPreview(_ units: [CGRect], in bounds: NSRect) {
        let frame = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        card.setFill(); frame.fill()
        border.setStroke(); frame.lineWidth = 1; frame.stroke()
        let area = bounds.insetBy(dx: 10, dy: 10)
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: text]
        for (i, u) in units.enumerated() {
            let r = NSRect(x: area.minX + u.minX * area.width + 3, y: area.minY + (1 - u.maxY) * area.height + 3,
                           width: u.width * area.width - 6, height: u.height * area.height - 6)
            let tile = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
            previewFill.setFill(); tile.fill()
            action.withAlphaComponent(0.55).setStroke(); tile.lineWidth = 1.5; tile.stroke()
            let s = NSString(string: "\(i + 1)"), size = s.size(withAttributes: attrs)
            s.draw(at: NSPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2), withAttributes: attrs)
        }
    }

    /// 拖拽吸附浮层：覆盖在其他软件之上，保持半透明。
    static func styleSnapOverlay(_ view: NSView) {
        paint(view, action.withAlphaComponent(0.16), radius: 10, border: action.withAlphaComponent(0.85))
        view.layer?.borderWidth = 2
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
