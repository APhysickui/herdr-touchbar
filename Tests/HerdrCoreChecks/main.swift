// Standalone tests also run on Macs with Command Line Tools but no XCTest.
import Foundation
import Darwin
import HerdrCore

struct CheckFailure: Error, CustomStringConvertible { let description: String }
func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailure(description: message) }
}
var failures = 0
var passes = 0
func test(_ name: String, _ body: () throws -> Void) {
    do { try body(); passes += 1; print("PASS \(name)") }
    catch { failures += 1; print("FAIL \(name): \(error)") }
}
func snapshot(_ panes: [[String: Any]], focused: String? = nil) throws -> SessionSnapshot {
    var value: [String: Any] = ["panes": panes, "tabs": [["tab_id": "w1:t1", "label": "研究任务"]], "protocol": 20]
    if let focused { value["focused_pane_id"] = focused }
    return try SessionSnapshot.decodeResponse(JSONSerialization.data(withJSONObject: ["result": ["snapshot": value]]))
}
func pane(_ id: String, _ agent: String?, _ state: String = "idle", label: String? = nil) -> [String: Any] {
    var value: [String: Any] = ["pane_id": id, "tab_id": "w1:t1", "agent_status": state, "focused": false, "cwd": "/tmp/project"]
    if let agent { value["agent"] = agent }
    if let label { value["label"] = label }
    return value
}
func rows(_ panes: [[String: Any]], focused: String? = nil) throws -> [AgentRow] {
    AgentRow.rows(from: try snapshot(panes, focused: focused), socket: "/one.sock", session: "one")
}

test("All five requested providers and future agents appear without a whitelist") {
    let providers = ["claude", "codex", "pi", "kimi", "opencode", "a-future-agent"]
    let r = try rows(providers.enumerated().map { pane("w1:p\($0.offset)", $0.element) })
    try require(r.map(\.provider) == providers, "Provider missing")
    try require(r.map(\.providerName) == ["CC", "Codex", "pi", "Kimi", "OpenCode", "a-future-agent"], "Incorrect names")
}
test("Same provider never overwrites another pane or another session") {
    let s = try snapshot([pane("w1:p1", "codex"), pane("w1:p2", "codex")])
    let r = AgentRow.rows(from: s, socket: "/one.sock", session: "one") + AgentRow.rows(from: s, socket: "/two.sock", session: "two")
    try require(Set(r.map(\.id)).count == 4, "Identity collision")
}
test("Shells are excluded and unrecognized states remain unknown") {
    let r = try rows([pane("w1:p1", nil), pane("w1:p2", ""), pane("w1:p3", "new", "future-state")])
    try require(r.count == 1 && r[0].state == .unknown, "False agent or false completion")
}
test("Attention precedes unseen completion, work and standby") {
    let states = ["idle", "working", "unknown", "blocked", "done"]
    let r = AgentRow.sorted(try rows(states.enumerated().map { pane("w1:p\($0.offset)", "codex", $0.element) }, focused: "w1:p0"))
    try require(r.map(\.state) == [.blocked, .done, .working, .idle, .unknown], "Wrong attention ordering")
}
test("Task labels win and generic placeholders are skipped") {
    var unnamed = pane("w1:p2", "codex"); unnamed["tokens"] = ["task": "待命 / 未命名任务"]
    let r = try rows([pane("w1:p1", "codex", label: "声子热霍尔理论推导"), unnamed])
    try require(r[0].task == "声子热霍尔理论推导" && r[1].task == "研究任务", "Wrong labels")
}
test("Focus uses session focus rather than per-tab focus") {
    let r = AgentRow.sorted(try rows([pane("w1:p1", "codex"), pane("w1:p2", "codex")], focused: "w1:p2"))
    try require(r.first?.paneID == "w1:p2" && r.filter(\.focused).count == 1, "Wrong focus")
}
test("A malformed snapshot fails instead of silently hiding live sessions") {
    let data = Data("{\"result\":{\"snapshot\":{\"panes\":[{\"pane_id\":\"w1:p1\"}],\"tabs\":[]}}}".utf8)
    do { _ = try SessionSnapshot.decodeResponse(data); throw CheckFailure(description: "Incomplete pane accepted") }
    catch is DecodingError { }
}

func withServer(response: String, body: (String) throws -> Void, inspect: (([String: Any]) -> Void)? = nil) throws {
    let path = "/tmp/htb-" + String(UUID().uuidString.prefix(8)) + ".sock"
    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw CheckFailure(description: "socket failed") }
    defer { Darwin.close(fd); unlink(path) }
    var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8) + [0]) }
    let bound = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard bound == 0 && Darwin.listen(fd, 1) == 0 else { throw CheckFailure(description: "bind: " + String(cString: strerror(errno))) }
    let group = DispatchGroup(); group.enter()
    DispatchQueue.global().async {
        defer { group.leave() }
        let client = accept(fd, nil, nil)
        guard client >= 0 else { return }
        defer { Darwin.close(client) }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var bytes = [UInt8](repeating: 0, count: 4096); var request = Data()
        while !request.contains(10) {
            let n = recv(client, &bytes, bytes.count, 0)
            if n <= 0 { return }; request.append(contentsOf: bytes.prefix(n))
        }
        if let value = try? JSONSerialization.jsonObject(with: request) as? [String: Any] { inspect?(value) }
        let data = Data((response + "\n").utf8)
        for half in [data.prefix(7), data.dropFirst(7)] {
            _ = half.withUnsafeBytes { send(client, $0.baseAddress, $0.count, 0) }
        }
    }
    defer { _ = group.wait(timeout: .now() + 4) }
    try body(path)
}
test("Fragmented socket responses are parsed and focus targets an explicit pane") {
    var captured: [String: Any] = [:]
    try withServer(response: "{\"id\":\"test\",\"result\":{\"type\":\"pane_focused\"}}", body: { path in
        let data = try HerdrSocket.request(path: path, method: "pane.focus", params: ["pane_id": "w2:p9"])
        try require(String(decoding: data, as: UTF8.self).contains("pane_focused"), "Truncated response")
    }, inspect: { captured = $0 })
    try require(captured["method"] as? String == "pane.focus", "Wrong method")
    try require((captured["params"] as? [String: String])?["pane_id"] == "w2:p9", "Wrong target")
    try require(captured["id"] as? String != nil, "Missing request ID")
}
test("A closed pane reports failure instead of focusing another pane") {
    try withServer(response: "{\"id\":\"test\",\"error\":{\"code\":\"pane_not_found\",\"message\":\"Pane was closed\"}}", body: { path in
        do {
            _ = try HerdrSocket.request(path: path, method: "pane.focus", params: ["pane_id": "old"])
            throw CheckFailure(description: "Expected remote error")
        } catch SocketError.remote(let message) { try require(message == "Pane was closed", "Wrong error") }
    })
}
test("Malformed socket responses are rejected") {
    try withServer(response: "{}", body: { path in
        do { _ = try HerdrSocket.request(path: path, method: "session.snapshot"); throw CheckFailure(description: "Expected invalid response") }
        catch SocketError.invalidResponse { }
    })
}
test("Oversized socket paths are rejected") {
    do { _ = try HerdrSocket.request(path: String(repeating: "x", count: 200), method: "ping"); throw CheckFailure(description: "Expected invalid path") }
    catch SocketError.invalidPath { }
}
print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
