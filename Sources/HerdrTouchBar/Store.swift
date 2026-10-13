import AppKit
import HerdrCore

struct DashboardState: Equatable {
    var rows: [AgentRow] = []
    var connections: [String: String] = [:] // Empty message means connected.
    var demo = false
    var actionError: String? = nil
    var connectedCount: Int { connections.values.filter { $0.isEmpty }.count }
    var liveRows: [AgentRow] { rows.filter { connections[$0.socket] == "" } }
    func isLive(_ row: AgentRow) -> Bool { demo || connections[row.socket] == "" }
    func count(_ state: AgentState) -> Int { liveRows.filter { $0.state == state }.count }
    var headline: String {
        if demo { return "DEMO · 界面演示" }
        if connectedCount == 0 { return connections.isEmpty ? "等待 Herdr" : "Herdr 已断开" }
        if connections.values.contains(where: { !$0.isEmpty }) { return "部分会话断开" }
        if count(.blocked) > 0 { return "\(count(.blocked)) 个任务等你处理" }
        if count(.working) > 0 { return "\(count(.working)) 个任务正在工作" }
        if count(.done) > 0 { return "\(count(.done)) 个任务已完成" }
        return "所有 agent 都在待命"
    }
}

final class DashboardStore {
    var state = DashboardState()
    var onChange: ((DashboardState) -> Void)?
    private let queue = DispatchQueue(label: "dev.herdr.touchbar.reader", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var lastRows: [String: [AgentRow]] = [:]
    private var sockets: [String] = []
    private var tick = 0

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(150))
        timer.setEventHandler { [weak self] in self?.poll() }
        self.timer = timer
        timer.resume()
    }
    func stop() { timer?.cancel(); timer = nil }
    private func poll() {
        if tick % 10 == 0 { sockets = HerdrSocket.discover() }
        tick += 1
        var next = DashboardState()
        for socket in sockets {
            do {
                let data = try HerdrSocket.request(path: socket, method: "session.snapshot")
                let snapshot = try SessionSnapshot.decodeResponse(data)
                let rows = AgentRow.rows(from: snapshot, socket: socket, session: HerdrSocket.sessionName(for: socket))
                lastRows[socket] = rows
                next.rows += rows
                next.connections[socket] = ""
            } catch {
                next.rows += lastRows[socket] ?? []
                next.connections[socket] = error.localizedDescription
            }
        }
        lastRows = lastRows.filter { sockets.contains($0.key) }
        next.rows = AgentRow.sorted(next.rows)
        let result = next
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Focus failures stay visible until the next successful interaction.
            var value = result
            value.actionError = self.state.actionError
            if self.state != value { self.state = value; self.onChange?(value) }
        }
    }
    func focus(_ row: AgentRow) {
        guard !state.demo, state.isLive(row) else { return }
        queue.async { [weak self] in
            do {
                _ = try HerdrSocket.request(path: row.socket, method: "pane.focus", params: ["pane_id": row.paneID])
                DispatchQueue.main.async {
                    self?.state.actionError = nil
                    // Only activate the Herdr host after the target was validated.
                    let bundle = UserDefaults.standard.string(forKey: "terminalBundleID") ?? "com.googlecode.iterm2"
                    if let terminal = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first {
                        terminal.activate(options: [.activateAllWindows])
                    }
                    self?.onChange?(self?.state ?? DashboardState())
                }
            } catch {
                DispatchQueue.main.async {
                    self?.state.actionError = "无法定位 \(row.paneID)：\(error.localizedDescription)"
                    self?.onChange?(self?.state ?? DashboardState())
                }
            }
        }
    }

    static func demoState() -> DashboardState {
        let tasks: [(String, String, AgentState)] = [
            ("claude", "支付模块 · 等待确认", .blocked), ("codex", "Herdr Touch Bar", .working),
            ("pi", "VO₂ 计算器件", .working), ("kimi", "文献阅读", .done),
            ("opencode", "前端组件", .working), ("codex", "声子热霍尔", .idle),
            ("claude", "API 集成", .idle), ("new-agent", "新的 agent 也能接入", .unknown)
        ]
        let rows = tasks.enumerated().map { index, task in
            AgentRow(socket: "demo", session: "default", paneID: "w1:p\(index + 1)", provider: task.0,
                     task: task.1, state: task.2, focused: index == 1)
        }
        return DashboardState(rows: AgentRow.sorted(rows), connections: ["demo": ""], demo: true)
    }
}
