import Foundation

public enum AgentState: String, Codable, CaseIterable {
    case working, blocked, done, idle, unknown
    public init(from decoder: Decoder) throws {
        self = AgentState(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
    public var priority: Int {
        switch self { case .blocked: return 0; case .done: return 1; case .working: return 2; case .idle: return 3; case .unknown: return 4 }
    }
    public var label: String {
        switch self { case .blocked: return "等你处理"; case .done: return "已完成"; case .working: return "工作中"; case .idle: return "待命"; case .unknown: return "状态未知" }
    }
    public var symbol: String {
        switch self { case .blocked: return "hand.raised.fill"; case .done: return "checkmark.circle.fill"; case .working: return "waveform"; case .idle: return "circle"; case .unknown: return "questionmark.circle" }
    }
}

public struct Pane: Decodable {
    public let pane_id: String
    public let tab_id: String
    public let agent: String?
    public let agent_status: AgentState
    public let focused: Bool
    public let cwd: String?
    public let foreground_cwd: String?
    public let label: String?
    public let title: String?
    public let agent_name: String?
    public let tokens: [String: String]?
}

public struct Tab: Decodable {
    public let tab_id: String
    public let label: String?
}

public struct SessionSnapshot: Decodable {
    public let panes: [Pane]
    public let tabs: [Tab]
    public let focused_pane_id: String?
    public let protocolVersion: Int?
    enum CodingKeys: String, CodingKey { case panes, tabs, focused_pane_id; case protocolVersion = "protocol" }

    public static func decodeResponse(_ data: Data) throws -> SessionSnapshot {
        struct Envelope: Decodable {
            struct Result: Decodable { let snapshot: SessionSnapshot }
            let result: Result
        }
        return try JSONDecoder().decode(Envelope.self, from: data).result.snapshot
    }
}

public struct AgentRow: Identifiable, Equatable {
    public let socket: String
    public let session: String
    public let paneID: String
    public let provider: String
    public let task: String
    public let state: AgentState
    public let focused: Bool
    public init(socket: String, session: String, paneID: String, provider: String, task: String, state: AgentState, focused: Bool) {
        self.socket = socket; self.session = session; self.paneID = paneID
        self.provider = provider; self.task = task; self.state = state; self.focused = focused
    }
    public var id: String { socket + "::" + paneID }
    public var providerName: String {
        switch provider.lowercased() {
        case "claude", "claude-code", "cc": return "CC"
        case "codex": return "Codex"
        case "pi": return "pi"
        case "kimi", "kimicode", "kimi-code": return "Kimi"
        case "opencode": return "OpenCode"
        default: return provider
        }
    }
    public var shortPaneID: String { paneID.split(separator: ":").last.map(String.init) ?? paneID }

    public static func rows(from snapshot: SessionSnapshot, socket: String, session: String) -> [AgentRow] {
        let tabs = Dictionary(snapshot.tabs.map { ($0.tab_id, $0.label ?? "") }, uniquingKeysWith: { a, _ in a })
        return snapshot.panes.compactMap { pane in
            guard let agent = pane.agent, !agent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let candidates = [pane.label, pane.title, pane.agent_name, pane.tokens?["task"], tabs[pane.tab_id],
                              pane.tokens?["folder"], pane.foreground_cwd.map { URL(fileURLWithPath: $0).lastPathComponent },
                              pane.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }]
            let generic = Set([agent.lowercased(), "cc", "claude", "codex", "pi", "kimi", "opencode", "待命 / 未命名任务"])
            let task = candidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty && !generic.contains($0.lowercased()) } ?? pane.pane_id
            return AgentRow(socket: socket, session: session, paneID: pane.pane_id, provider: agent,
                            task: task, state: pane.agent_status, focused: pane.pane_id == snapshot.focused_pane_id)
        }
    }
    public static func sorted(_ rows: [AgentRow]) -> [AgentRow] {
        rows.sorted {
            if $0.state.priority != $1.state.priority { return $0.state.priority < $1.state.priority }
            if $0.focused != $1.focused { return $0.focused }
            return $0.id.localizedStandardCompare($1.id) == .orderedAscending
        }
    }
}
