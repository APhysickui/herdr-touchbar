import AppKit
import QuartzCore
import HerdrCore

enum Design {
    static let background = color(0xF2F1EB), panel = color(0xFAF9F4), line = color(0xD5D5CE)
    static let ink = color(0x20231F), muted = color(0x777B78), blue = color(0x294BFF)
    static let cyan = color(0x8CCBFF), amber = color(0xE4A047), white = color(0xF7F8FF)
    static let barPanel = color(0x101A35)
    static func color(_ hex: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
    static func stateColor(_ state: AgentState, onBar: Bool = false) -> NSColor {
        switch state {
        case .working: return onBar ? cyan : blue
        case .blocked: return onBar ? color(0xFFD18B) : color(0xAA620D)
        case .done: return onBar ? color(0x8EE2D7) : color(0x227F75)
        case .idle: return onBar ? color(0x8792AF) : muted
        case .unknown: return onBar ? color(0xB0A8C8) : color(0x827793)
        }
    }
    // Concrete font faces avoid dynamic system-font resolution in remote Touch Bar drawing.
    static func font(size: CGFloat, weight: NSFont.Weight, mono: Bool, display: Bool = false) -> NSFont {
        let name = display ? "HelveticaNeue-CondensedBlack" : mono ? (weight.rawValue >= NSFont.Weight.semibold.rawValue ? "Menlo-Bold" : "Menlo-Regular")
            : weight.rawValue >= NSFont.Weight.semibold.rawValue ? "HelveticaNeue-Bold" : "HelveticaNeue"
        return NSFont(name: name, size: size) ?? NSFont(name: "Arial", size: size)!
    }
    static func text(_ value: String, _ rect: NSRect, size: CGFloat, color: NSColor = ink,
                     weight: NSFont.Weight = .regular, mono: Bool = false, alignment: NSTextAlignment = .left, display: Bool = false) {
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail; paragraph.alignment = alignment
        (value as NSString).draw(in: rect, withAttributes: [.font: font(size: size, weight: weight, mono: mono, display: display),
                                                          .foregroundColor: color, .paragraphStyle: paragraph])
    }
    static func rounded(_ rect: NSRect, radius: CGFloat, fill: NSColor, border: NSColor? = nil) {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        fill.setFill(); path.fill()
        if let border { border.setStroke(); path.lineWidth = 1; path.stroke() }
    }
    static func symbol(_ name: String, in rect: NSRect, color: NSColor) {
        guard let original = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
        let image = NSImage(size: rect.size, flipped: false) { bounds in
            original.draw(in: bounds); color.setFill(); bounds.fill(using: .sourceAtop); return true
        }
        image.draw(in: rect)
    }
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

final class AgentChip: NSControl {
    let row: AgentRow
    let live: Bool
    var onTap: ((AgentRow) -> Void)?
    private var pressed = false
    private let sweep = CAGradientLayer()
    override var isFlipped: Bool { true }
    init(row: AgentRow, live: Bool) {
        self.row = row; self.live = live
        super.init(frame: NSRect(x: 0, y: 0, width: 150, height: 30))
        wantsLayer = true; layer?.cornerRadius = 5; layer?.masksToBounds = true
        sweep.colors = [NSColor.clear.cgColor, Design.cyan.withAlphaComponent(0.19).cgColor, NSColor.clear.cgColor]
        sweep.startPoint = CGPoint(x: 0, y: 0.2); sweep.endPoint = CGPoint(x: 1, y: 0.8)
        layer?.addSublayer(sweep)
        if live && row.state == .working && !Design.reduceMotion {
            let animation = CABasicAnimation(keyPath: "transform.translation.x")
            animation.fromValue = -150; animation.toValue = 150; animation.duration = 3.2
            animation.repeatCount = .infinity; sweep.add(animation, forKey: "workingSweep")
        } else { sweep.isHidden = true }
        setAccessibilityElement(true); setAccessibilityRole(.button)
        setAccessibilityLabel("\(row.providerName)，\(row.task)，\(live ? row.state.label : "已断开")，\(row.paneID)")
        toolTip = "\(row.providerName) · \(row.task)\n\(row.session) / \(row.paneID) · \(live ? row.state.label : "已断开")"
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); sweep.frame = bounds }
    override func draw(_ dirtyRect: NSRect) {
        let active = live && row.state == .working
        let accent = live ? Design.stateColor(row.state, onBar: true) : Design.muted
        Design.rounded(bounds.insetBy(dx: 1, dy: 1), radius: 5,
                       fill: pressed ? Design.color(0x4168FF) : active ? Design.blue : Design.barPanel,
                       border: row.focused && live ? Design.cyan : Design.color(0x263553))
        Design.text(row.providerName, NSRect(x: 10, y: 3, width: 94, height: 15), size: 11,
                    color: live ? Design.white : Design.muted, weight: .semibold)
        Design.text(row.shortPaneID, NSRect(x: bounds.width - 32, y: 4, width: 23, height: 12), size: 8,
                    color: active ? Design.cyan : Design.color(0x7E90B5), mono: true, alignment: .right)
        Design.text(row.task, NSRect(x: 10, y: 17, width: bounds.width - 33, height: 11), size: 8.5,
                    color: live ? Design.white.withAlphaComponent(0.8) : Design.muted)
        Design.symbol(live ? row.state.symbol : "wifi.slash", in: NSRect(x: bounds.width - 19, y: 18, width: 9, height: 9), color: accent)
        if row.state == .blocked && live { Design.amber.setFill(); NSRect(x: 3, y: 6, width: 2, height: 18).fill() }
    }
    override func mouseDown(with event: NSEvent) { if live { pressed = true; needsDisplay = true } }
    override func mouseUp(with event: NSEvent) {
        guard pressed else { return }; pressed = false; needsDisplay = true
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onTap?(row) }
    }
    override func accessibilityPerformPress() -> Bool { if live { onTap?(row) }; return live }
}

final class SummaryButton: NSControl {
    var state = DashboardState() { didSet { needsDisplay = true } }
    var onTap: (() -> Void)?
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        Design.rounded(bounds.insetBy(dx: 1, dy: 1), radius: 5, fill: Design.color(0x192A60))
        Design.text("HERDR ↗", NSRect(x: 8, y: 3, width: 78, height: 14), size: 10.5, color: Design.white, weight: .semibold)
        let label = state.demo ? "界面演示" : state.connectedCount == 0 ? "等待连接" : "\(state.count(.working)) 工作  \(state.count(.blocked)) 等待"
        Design.text(label, NSRect(x: 8, y: 17, width: 82, height: 11), size: 8, color: Design.cyan)
    }
    override func mouseUp(with event: NSEvent) { onTap?() }
    override func accessibilityPerformPress() -> Bool { onTap?(); return true }
}

final class StripView: NSView {
    private let summary = SummaryButton(), scroll = NSScrollView(), document = NSView()
    var onFocus: ((AgentRow) -> Void)?
    var onDashboard: (() -> Void)?
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        summary.setAccessibilityElement(true); summary.setAccessibilityRole(.button)
        summary.setAccessibilityLabel("打开 Herdr 状态面板")
        summary.onTap = { [weak self] in self?.onDashboard?() }
        scroll.drawsBackground = false; scroll.hasHorizontalScroller = false; scroll.hasVerticalScroller = false
        scroll.horizontalScrollElasticity = .allowed; scroll.verticalScrollElasticity = .none
        scroll.documentView = document; addSubview(summary); addSubview(scroll)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout(); summary.frame = NSRect(x: 0, y: 0, width: 94, height: bounds.height)
        scroll.frame = NSRect(x: 100, y: 0, width: max(0, bounds.width - 100), height: bounds.height)
    }
    func update(_ state: DashboardState, activeOnly: Bool = false) {
        summary.state = state
        let previous = scroll.contentView.bounds.origin
        document.subviews.forEach { $0.removeFromSuperview() }
        let rows = state.rows.filter { !activeOnly || $0.state != .idle || !state.isLive($0) }
        for (index, row) in rows.enumerated() {
            let chip = AgentChip(row: row, live: state.isLive(row))
            chip.frame = NSRect(x: CGFloat(index) * 156, y: 0, width: 150, height: 30)
            chip.onTap = { [weak self] in self?.onFocus?($0) }; document.addSubview(chip)
        }
        document.frame = NSRect(x: 0, y: 0, width: max(1, CGFloat(rows.count) * 156 - 6), height: 30)
        if rows.isEmpty {
            let text = NSTextField(labelWithString: state.connectedCount == 0 ? "启动 Herdr，agent 会自动出现在这里" : "暂时没有活跃会话")
            text.font = Design.font(size: 11, weight: .regular, mono: false); text.textColor = Design.cyan
            text.frame = NSRect(x: 8, y: 7, width: 330, height: 18); document.addSubview(text)
            document.setFrameSize(NSSize(width: 350, height: 30))
        }
        scroll.contentView.scroll(to: NSPoint(x: min(previous.x, max(0, document.frame.width - scroll.frame.width)), y: 0))
        scroll.reflectScrolledClipView(scroll.contentView); needsLayout = true
    }
}

final class AgentCard: NSControl {
    let row: AgentRow
    let live: Bool
    var onTap: ((AgentRow) -> Void)?
    override var isFlipped: Bool { true }
    init(row: AgentRow, live: Bool) {
        self.row = row; self.live = live; super.init(frame: .zero)
        setAccessibilityElement(true); setAccessibilityRole(.button)
        setAccessibilityLabel("\(row.providerName)，\(row.task)，\(live ? row.state.label : "连接已断开")，\(row.paneID)")
        toolTip = "\(row.providerName) · \(row.task) · \(row.paneID)"
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let accent = live ? Design.stateColor(row.state) : Design.muted
        let active = row.focused && live
        Design.rounded(bounds.insetBy(dx: 1, dy: 1), radius: 3, fill: active ? Design.blue : Design.panel,
                       border: active ? Design.blue : Design.line)
        Design.text(row.providerName.uppercased(), NSRect(x: 15, y: 13, width: 88, height: 21), size: 12,
                    color: active ? Design.white : Design.blue, weight: .semibold)
        Design.text(row.shortPaneID, NSRect(x: 15, y: 37, width: 80, height: 15), size: 9,
                    color: active ? Design.cyan : Design.muted, mono: true)
        Design.text(row.task, NSRect(x: 110, y: 11, width: bounds.width - 219, height: 23), size: 14,
                    color: active ? Design.white : live ? Design.ink : Design.muted, weight: .semibold)
        Design.text(row.session, NSRect(x: 111, y: 38, width: bounds.width - 221, height: 15), size: 9,
                    color: active ? Design.cyan : Design.muted)
        Design.symbol(live ? row.state.symbol : "wifi.slash", in: NSRect(x: bounds.width - 98, y: 15, width: 12, height: 12), color: active ? Design.white : accent)
        Design.text(live ? row.state.label : "已断开", NSRect(x: bounds.width - 78, y: 14, width: 67, height: 17), size: 10, color: active ? Design.white : accent)
        Design.text("↗", NSRect(x: bounds.width - 28, y: 35, width: 18, height: 22), size: 17, color: active ? Design.cyan : Design.blue)
    }
    override func mouseUp(with event: NSEvent) { if live && bounds.contains(convert(event.locationInWindow, from: nil)) { onTap?(row) } }
    override func accessibilityPerformPress() -> Bool { if live { onTap?(row) }; return live }
}
final class FlippedView: NSView { override var isFlipped: Bool { true } }

final class BlueActionButton: NSControl {
    var onTap: (() -> Void)?
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame); setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityLabel("显示 Touch Bar")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        Design.rounded(bounds, radius: 2, fill: Design.blue)
        Design.text("显示 Touch Bar", NSRect(x: 18, y: 13, width: bounds.width - 58, height: 24), size: 13, color: Design.white, weight: .semibold)
        Design.text("↗", NSRect(x: bounds.width - 40, y: 6, width: 29, height: 33), size: 27, color: Design.white)
    }
    override func mouseUp(with event: NSEvent) { if bounds.contains(convert(event.locationInWindow, from: nil)) { onTap?() } }
    override func accessibilityPerformPress() -> Bool { onTap?(); return true }
}

final class OrbitView: NSView {
    private let orbit = CAShapeLayer()
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true
        orbit.fillColor = nil; orbit.strokeColor = Design.blue.withAlphaComponent(0.5).cgColor
        orbit.lineWidth = 1; orbit.lineDashPattern = [3, 5]; layer?.addSublayer(orbit)
        if !Design.reduceMotion {
            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.fromValue = 0; rotation.toValue = 2 * Double.pi; rotation.duration = 28; rotation.repeatCount = .infinity
            orbit.add(rotation, forKey: "orbit")
            let drift = CABasicAnimation(keyPath: "transform.translation.y")
            drift.fromValue = -3; drift.toValue = 4; drift.autoreverses = true; drift.duration = 3; drift.repeatCount = .infinity
            layer?.add(drift, forKey: "drift")
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout(); orbit.frame = bounds.insetBy(dx: 8, dy: 8)
        orbit.path = CGPath(ellipseIn: CGRect(origin: .zero, size: orbit.bounds.size), transform: nil)
    }
    override func draw(_ dirtyRect: NSRect) {
        let c = NSPoint(x: bounds.midX, y: bounds.midY), r = min(bounds.width, bounds.height) * 0.34
        let ring = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        Design.blue.withAlphaComponent(0.13).setStroke(); ring.lineWidth = 1; ring.stroke()
        let paths = NSBezierPath()
        for i in 0..<8 {
            let a = CGFloat(i) * .pi / 4
            paths.move(to: NSPoint(x: c.x + cos(a) * r * 0.47, y: c.y + sin(a) * r * 0.47))
            paths.line(to: NSPoint(x: c.x + cos(a) * r * 1.01, y: c.y + sin(a) * r * 1.01))
        }
        Design.blue.setStroke(); paths.lineWidth = 5; paths.stroke()
        Design.rounded(NSRect(x: c.x - 26, y: c.y - 26, width: 52, height: 52), radius: 26, fill: Design.blue)
        Design.text("H", NSRect(x: c.x - 25, y: c.y - 18, width: 50, height: 38), size: 30,
                    color: Design.white, weight: .bold, alignment: .center, display: true)
    }
}

final class DashboardView: NSView {
    var state = DashboardState(), activeOnly = false
    var onFocus: ((AgentRow) -> Void)?
    var onShowBar: (() -> Void)?
    let strip = StripView()
    private let list = NSScrollView(), document = FlippedView(), barButton = BlueActionButton(), orbit = OrbitView()
    private let filter = NSButton(checkboxWithTitle: "只看活跃会话", target: nil, action: nil)
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true; layer?.backgroundColor = Design.background.cgColor
        strip.onFocus = { [weak self] in self?.onFocus?($0) }; addSubview(strip)
        list.drawsBackground = false; list.hasVerticalScroller = true; list.autohidesScrollers = true
        list.documentView = document; addSubview(list)
        barButton.onTap = { [weak self] in self?.onShowBar?() }; addSubview(barButton)
        filter.target = self; filter.action = #selector(toggleFilter)
        filter.attributedTitle = NSAttributedString(string: "只看活跃会话", attributes: [.foregroundColor: Design.muted,
                                            .font: Design.font(size: 11, weight: .regular, mono: false)])
        addSubview(filter); addSubview(orbit)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func toggleFilter() { activeOnly = filter.state == .on; update(state) }
    override func layout() {
        super.layout()
        strip.frame = NSRect(x: 45, y: bounds.height - 108, width: bounds.width - 90, height: 30)
        list.frame = NSRect(x: 414, y: 252, width: bounds.width - 459, height: max(110, bounds.height - 400))
        barButton.frame = NSRect(x: 45, y: 511, width: 268, height: 48)
        filter.frame = NSRect(x: bounds.width - 153, y: 222, width: 114, height: 21)
        orbit.frame = NSRect(x: 98, y: 565, width: 156, height: max(60, min(100, bounds.height - 705)))
        orbit.isHidden = bounds.height < 760; layoutCards()
    }
    private func layoutCards() {
        for (i, card) in document.subviews.enumerated() { card.frame = NSRect(x: 0, y: CGFloat(i) * 73, width: list.bounds.width - 2, height: 63) }
        document.frame = NSRect(x: 0, y: 0, width: list.bounds.width, height: max(list.bounds.height, CGFloat(document.subviews.count) * 73))
    }
    func update(_ state: DashboardState) {
        self.state = state; strip.update(state, activeOnly: activeOnly)
        let origin = list.contentView.bounds.origin; document.subviews.forEach { $0.removeFromSuperview() }
        for row in state.rows where !activeOnly || row.state != .idle || !state.isLive(row) {
            let card = AgentCard(row: row, live: state.isLive(row)); card.onTap = { [weak self] in self?.onFocus?($0) }; document.addSubview(card)
        }
        layoutCards(); list.contentView.scroll(to: NSPoint(x: 0, y: min(origin.y, max(0, document.bounds.height - list.bounds.height))))
        list.reflectScrolledClipView(list.contentView); needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        Design.background.setFill(); bounds.fill()
        Design.text("✳", NSRect(x: 43, y: 22, width: 27, height: 30), size: 25, color: Design.blue)
        Design.text("HERDR / TOUCH BAR", NSRect(x: 80, y: 29, width: 260, height: 19), size: 11, weight: .semibold, mono: true)
        let badge = state.demo ? "○ 界面演示" : state.connectedCount > 0 ? "● 实时在线" : "○ 等待 Herdr"
        Design.text(badge, NSRect(x: bounds.width - 181, y: 29, width: 138, height: 19), size: 11,
                    color: state.connectedCount > 0 ? Design.blue : Design.muted, alignment: .right)
        Design.ink.setFill(); NSRect(x: 45, y: 64, width: bounds.width - 90, height: 1).fill()
        for (i, word) in ["ALL.", "AGENTS.", "LIVE."].enumerated() {
            Design.text(word, NSRect(x: 39, y: 82 + CGFloat(i) * 105, width: 340, height: 123), size: 100, color: Design.blue, display: true)
        }
        Design.text("工作交给它们。", NSRect(x: 46, y: 422, width: 300, height: 33), size: 24, weight: .semibold)
        Design.text("注意力留给你。", NSRect(x: 46, y: 461, width: 300, height: 27), size: 17, color: Design.muted)
        Design.text("01 / YOUR AGENTS, ALWAYS IN SIGHT", NSRect(x: 415, y: 92, width: bounds.width - 470, height: 20), size: 9, color: Design.muted, mono: true)
        Design.text(state.headline, NSRect(x: 413, y: 124, width: bounds.width - 458, height: 45), size: 28, weight: .semibold)
        let metrics: [(AgentState, String)] = [(.working, "工作中"), (.blocked, "等你处理"), (.done, "已完成"), (.idle, "待命")]
        let width = (bounds.width - 459) / 4
        for (i, metric) in metrics.enumerated() {
            let x = 415 + CGFloat(i) * width
            Design.text(String(format: "%02d", state.count(metric.0)), NSRect(x: x, y: 169, width: 53, height: 36), size: 26, color: Design.stateColor(metric.0), display: true)
            Design.text(metric.1, NSRect(x: x + 39, y: 181, width: width - 42, height: 18), size: 10, color: Design.muted)
        }
        Design.line.setFill(); NSRect(x: 415, y: 215, width: bounds.width - 460, height: 1).fill()
        Design.text("会话 / \(state.rows.count)", NSRect(x: 415, y: 227, width: 220, height: 18), size: 11, color: Design.muted)
        if state.rows.isEmpty {
            Design.text(state.connectedCount == 0 ? "启动 Herdr 后，会话会自动出现在这里。" : "当前没有正在运行的 agent。", NSRect(x: 430, y: 289, width: bounds.width - 490, height: 40), size: 14, color: Design.muted)
        }
        Design.line.setFill(); NSRect(x: 45, y: bounds.height - 147, width: bounds.width - 90, height: 1).fill()
        Design.text("02 / THE TOUCH BAR", NSRect(x: 45, y: bounds.height - 137, width: 230, height: 17), size: 9, color: Design.blue, mono: true)
        Design.text("滑动查看全部 · 点击返回对应会话", NSRect(x: bounds.width - 300, y: bounds.height - 136, width: 256, height: 17), size: 10, color: Design.muted, alignment: .right)
        Design.rounded(NSRect(x: 37, y: bounds.height - 115, width: bounds.width - 74, height: 44), radius: 8, fill: Design.color(0x070E1E))
        let footer = state.actionError ?? (state.connections.values.first(where: { !$0.isEmpty }).map { "连接异常：" + $0 }
            ?? (state.demo ? "这是界面演示；真实模式会自动显示你的 Herdr 会话。" : "切换窗口，状态一直在线。"))
        Design.text(footer, NSRect(x: 45, y: bounds.height - 43, width: bounds.width - 220, height: 18), size: 10,
                    color: state.actionError == nil ? Design.muted : Design.stateColor(.blocked))
        Design.text("LOCAL ONLY ↗", NSRect(x: bounds.width - 172, y: bounds.height - 43, width: 127, height: 18), size: 9, color: Design.blue, mono: true, alignment: .right)
    }
    func savePNG(to path: String) throws {
        layoutSubtreeIfNeeded()
        guard let bitmap = bitmapImageRepForCachingDisplay(in: bounds) else { throw SocketError.invalidResponse }
        cacheDisplay(in: bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw SocketError.invalidResponse }
        try data.write(to: URL(fileURLWithPath: path))
    }
}
