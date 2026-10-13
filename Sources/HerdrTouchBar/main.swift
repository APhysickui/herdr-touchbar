import AppKit
import HerdrCore
import TouchBarBridge

let args = CommandLine.arguments
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func readLiveState() -> DashboardState {
    var result = DashboardState()
    for socket in HerdrSocket.discover() {
        do {
            let response = try HerdrSocket.request(path: socket, method: "session.snapshot")
            let snapshot = try SessionSnapshot.decodeResponse(response)
            result.rows += AgentRow.rows(from: snapshot, socket: socket, session: HerdrSocket.sessionName(for: socket))
            result.connections[socket] = ""
        } catch { result.connections[socket] = error.localizedDescription }
    }
    result.rows = AgentRow.sorted(result.rows)
    return result
}

if args.contains("--diagnose") {
    let state = readLiveState()
    let data: [String: Any] = ["touchBarAPI": HTBAvailable(), "connectedSessions": state.connectedCount,
        "frontmostApp": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown",
        "connections": state.connections,
        "agents": state.rows.map { ["agent": $0.provider, "pane": $0.paneID, "session": $0.session, "state": $0.state.rawValue] }]
    let json = try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: json, as: UTF8.self))
    exit(state.connectedCount > 0 ? 0 : 1)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

if let path = option("--render-icon") {
    let image = NSImage(size: NSSize(width: 1024, height: 1024))
    image.lockFocus()
    Design.rounded(NSRect(x: 52, y: 52, width: 920, height: 920), radius: 205, fill: Design.blue)
    Design.text("H", NSRect(x: 180, y: 200, width: 664, height: 684), size: 570, color: Design.white,
                weight: .bold, alignment: .center, display: true)
    for i in 0..<3 {
        Design.rounded(NSRect(x: 268 + CGFloat(i) * 170, y: 193, width: 145, height: 29), radius: 6,
                       fill: i == 0 ? Design.white : Design.cyan.withAlphaComponent(CGFloat(4 - i) / 5))
    }
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    exit(0)
}

if let path = option("--render") ?? option("--render-live") {
    let state = args.contains("--render-live") ? readLiveState() : DashboardStore.demoState()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 810), styleMask: [.borderless], backing: .buffered, defer: false)
    let view = DashboardView(frame: NSRect(x: 0, y: 0, width: 1080, height: 810))
    view.appearance = NSAppearance(named: .aqua)
    window.contentView = view
    view.update(state)
    try view.savePNG(to: path)
    print("Rendered \(path)")
    exit(0)
}

if args.contains("--stress-render") {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 810), styleMask: [.borderless], backing: .buffered, defer: false)
    let view = DashboardView(frame: NSRect(x: 0, y: 0, width: 1080, height: 810)); window.contentView = view
    for i in 0..<120 {
        autoreleasepool {
            var state = DashboardStore.demoState()
            if i % 2 == 0 { state.connections["demo"] = "测试断线"; state.demo = false }
            view.activeOnly = i % 3 == 0; view.update(state); view.layoutSubtreeIfNeeded()
            if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) { view.cacheDisplay(in: view.bounds, to: bitmap) }
        }
    }
    print("PASS 120 native renders: mixed agents, reconnects, filtering, Chinese labels")
    exit(0)
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = DashboardStore()
    var touchBar: TouchBarController!
    var statusItem: NSStatusItem!
    var window: NSWindow!
    var dashboard: DashboardView!
    private var activeOnly = false
    private var ownsInstanceLock = false
    private let lockFD: Int32 = {
        let directory = NSHomeDirectory() + "/Library/Application Support/HerdrTouchBar"
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        return Darwin.open(directory + "/instance.lock", O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent two helpers competing for the global Touch Bar.
        if lockFD >= 0 && flock(lockFD, LOCK_EX | LOCK_NB) != 0 { NSApp.terminate(nil); return }
        ownsInstanceLock = lockFD >= 0
        NSApp.appearance = NSAppearance(named: .aqua)
        touchBar = TouchBarController()
        touchBar.strip.onFocus = { [weak self] in self?.store.focus($0) }
        touchBar.strip.onDashboard = { [weak self] in self?.showDashboard() }
        let size = NSSize(width: 1080, height: 810)
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Herdr Touch Bar"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Design.background
        window.minSize = NSSize(width: 960, height: 740)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        dashboard = DashboardView(frame: NSRect(origin: .zero, size: size))
        dashboard.onFocus = { [weak self] in self?.store.focus($0) }
        dashboard.onShowBar = { [weak self] in self?.touchBar.show() }
        window.contentView = dashboard
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "Herdr Touch Bar")
        statusItem.button?.imagePosition = .imageLeading
        statusItem.menu = makeMenu()
        store.onChange = { [weak self] in self?.update($0) }
        if args.contains("--demo") {
            store.state = DashboardStore.demoState(); update(store.state); showDashboard()
        } else {
            store.start()
            if !UserDefaults.standard.bool(forKey: "hasLaunched") || args.contains("--show") { showDashboard() }
            UserDefaults.standard.set(true, forKey: "hasLaunched")
        }
        touchBar.show()
    }
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        func item(_ title: String, _ selector: Selector, key: String = "") {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key); item.target = self; menu.addItem(item)
        }
        item("打开状态面板", #selector(showDashboard))
        item("显示 Touch Bar", #selector(showTouchBar))
        item("收起 Touch Bar", #selector(hideTouchBar))
        let filter = NSMenuItem(title: "Touch Bar 隐藏待命会话", action: #selector(toggleActive(_:)), keyEquivalent: "")
        filter.target = self; menu.addItem(filter)
        menu.addItem(.separator())
        let host = NSMenuItem(title: "Herdr 所在终端", action: nil, keyEquivalent: "")
        let terminals = NSMenu()
        for (title, bundle) in [("iTerm2", "com.googlecode.iterm2"), ("Ghostty", "com.mitchellh.ghostty"), ("Terminal", "com.apple.Terminal")] {
            let entry = NSMenuItem(title: title, action: #selector(selectTerminal(_:)), keyEquivalent: "")
            entry.target = self; entry.representedObject = bundle
            entry.state = bundle == (UserDefaults.standard.string(forKey: "terminalBundleID") ?? "com.googlecode.iterm2") ? .on : .off
            terminals.addItem(entry)
        }
        host.submenu = terminals; menu.addItem(host)
        menu.addItem(.separator())
        item("退出 Herdr Touch Bar", #selector(quit), key: "q")
        return menu
    }
    @objc private func selectTerminal(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.representedObject as? String, forKey: "terminalBundleID")
        sender.menu?.items.forEach { $0.state = $0 === sender ? .on : .off }
    }
    private func update(_ state: DashboardState) {
        dashboard.update(state)
        touchBar.strip.update(state, activeOnly: activeOnly)
        statusItem.button?.title = state.count(.blocked) > 0 ? " \(state.count(.blocked)) !" : " \(state.count(.working))"
        statusItem.button?.contentTintColor = state.count(.blocked) > 0 ? Design.amber : state.connectedCount == 0 ? Design.muted : Design.blue
        statusItem.button?.toolTip = state.headline
    }
    @objc func showDashboard() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc private func showTouchBar() { touchBar.show() }
    @objc private func hideTouchBar() { touchBar.hide() }
    @objc private func toggleActive(_ sender: NSMenuItem) {
        activeOnly.toggle(); sender.state = activeOnly ? .on : .off
        touchBar.strip.update(store.state, activeOnly: activeOnly)
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDashboard()
        return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        store.stop(); touchBar?.shutdown()
        if ownsInstanceLock { flock(lockFD, LOCK_UN); Darwin.close(lockFD) }
    }
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
