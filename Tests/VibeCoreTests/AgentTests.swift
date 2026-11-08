import XCTest
@testable import VibeCore

final class AgentTests: XCTestCase {
    let node = "/opt/homebrew/bin/node"
    let d0 = Date(timeIntervalSince1970: 0)

    func testCodexAndGeminiSessions() {
        let list = [
            makeProcess(10, 1, "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"),
            makeProcess(11, 10, "/bin/zsh"),
            // Codex installed with npm: a node wrapper with the codex executable as child. Grouped into one session.
            makeProcess(12, 11, node, fp: 50, args: ["node", "/opt/homebrew/lib/node_modules/@openai/codex/bin/codex.js"]),
            makeProcess(13, 12, "/opt/homebrew/lib/node_modules/@openai/codex/vendor/aarch64-apple-darwin/codex/codex", fp: 120),
            makeProcess(14, 13, node, fp: 30, args: ["node", "/x/node_modules/@modelcontextprotocol/server-memory/index.js"]),
            makeProcess(15, 11, node, fp: 200, args: ["node", "/opt/homebrew/bin/gemini"]),
            // Codex inside the Codex app: belongs to the app, not a CLI session.
            makeProcess(16, 1, "/Applications/Codex.app/Contents/Resources/codex", fp: 90)
        ]
        let items = AgentSessionBuilder.from(list, cpu: [:], directory: { $0 == 12 ? "/Users/u/shop" : nil }, lastActive: { _, _ in self.d0 })
        XCTAssertEqual(items.map(\.tool).sorted(), ["Codex CLI", "Gemini CLI"])
        let codex = items.first { $0.tool == "Codex CLI" }
        XCTAssertEqual(codex?.pid, 12)
        XCTAssertEqual(codex?.footprint, 200)
        XCTAssertEqual(codex?.projectName, "shop")
    }

    func testCollectsTools() {
        let app = { (name: String, bundlePath: String, fp: UInt64) in
            AppUsage(app: RunningApp(pid: 1, bundleId: nil, name: name, bundlePath: bundlePath, isFrontmost: false),
                      footprint: fp, cpu: 0, processCount: 1, startDate: self.d0, lastActive: self.d0)
        }
        let vm = ItemUsage(group: .claude, name: ItemName.claudeVM, footprint: 1000, cpu: 0, processCount: 1,
                           earliestStart: d0, lastActive: d0)
        let pc = { (pid: Int32, fp: UInt64) in
            ClaudeCodeSession(id: "p\(pid)", pid: pid, startDate: self.d0, footprint: fp, cpu: 0, directory: nil, lastActive: self.d0)
        }
        var result = ProcessSnapshot(timestamp: d0, processes: [],
                                 groups: [GroupUsage(group: .claude, footprint: 1000, cpu: 0, processCount: 1, items: [vm])],
                                 sessions: [pc(1, 300), pc(2, 200)], readableTotal: 0, unreadableCount: 0)
        result.apps = [app("Claude", "/Applications/Claude.app", 500), app("ChatGPT", "/Applications/ChatGPT.app", 800),
                      app("Cursor", "/Applications/Cursor.app", 900), app("Zalo", "/Applications/Zalo.app", 700)]
        result.agentSessions = [AgentSession(id: "c", pid: 9, tool: "Codex CLI", directory: nil, footprint: 100, cpu: 0, startDate: d0, lastActive: d0)]

        let items = AIToolBuilder.from(result)
        XCTAssertEqual(items.map(\.name), ["Claude Code", "Codex CLI", AIToolBuilder.coworkVMName, "ChatGPT", "Claude", "Cursor"])
        XCTAssertEqual(items[0].sessions.count, 2)
        XCTAssertEqual(items[0].footprint, 500)
        // The Claude app's virtual machine (Cowork) has its own row.
        XCTAssertEqual(items.first { $0.name == "Claude" }?.footprint, 500)
        XCTAssertEqual(items.first { $0.name == AIToolBuilder.coworkVMName }?.footprint, 1000)
        XCTAssertFalse(items.contains { $0.name == "Zalo" })
    }

    func testSessionHeadroom() {
        // 8 GB Mac, 1 GB wired, apps need 4 GB more. Left: 8 - 0.5 reserve - 5 = 2.5 GB.
        let memoryInfo = Memory.fromPageCounts(internalPages: 0, purgeable: 0, wired: 1 << 30, compressor: 0, external: 0, free: 0,
                                 pageSize: 1, total: 8 << 30)
        let result = ProcessSnapshot(timestamp: d0, processes: [],
                                 groups: [GroupUsage(group: .other, footprint: 4 << 30, cpu: 0, processCount: 1, items: [])],
                                 sessions: [], readableTotal: 0, unreadableCount: 0)
        let budget = RAMBudget(memory: memoryInfo, snapshot: result)
        let p = { (fp: UInt64) in AgentSession(id: "\(fp)", pid: 1, tool: "Claude Code", directory: nil, footprint: fp, cpu: 0,
                                             startDate: self.d0, lastActive: self.d0) }
        let c = SessionHeadroom(budget: budget, sessions: [p(400 << 20), p(600 << 20)])
        XCTAssertEqual(c.perSession, 500 << 20)
        XCTAssertEqual(c.availableRAM, UInt64(2.5 * Double(1 << 30)))
        XCTAssertEqual(c.sessionCount, 5)
        XCTAssertEqual(c.state, .room(5))
        // No sessions yet: use the default.
        XCTAssertEqual(SessionHeadroom(budget: budget, sessions: []).perSession, SessionHeadroom.defaultValue)

        // RAM already exceeded: no room left.
        let result2 = ProcessSnapshot(timestamp: d0, processes: [],
                                  groups: [GroupUsage(group: .other, footprint: 10 << 30, cpu: 0, processCount: 1, items: [])],
                                  sessions: [], readableTotal: 0, unreadableCount: 0)
        let c2 = SessionHeadroom(budget: RAMBudget(memory: memoryInfo, snapshot: result2), sessions: [])
        XCTAssertEqual(c2.sessionCount, 0)
        XCTAssertEqual(c2.overflow, 3 << 30)
        // Over budget: the UI must say the Mac is short of RAM, not show "0 sessions left".
        XCTAssertEqual(c2.state, .short)
    }

    /// Within budget but less than one session left: "tight", not "short".
    func testHeadroomTight() {
        let memory = Memory.fromPageCounts(internalPages: 0, purgeable: 0, wired: 1 << 30, compressor: 0, external: 0, free: 0,
                                           pageSize: 1, total: 8 << 30)
        let result = ProcessSnapshot(timestamp: Date(timeIntervalSince1970: 0), processes: [],
                                     groups: [GroupUsage(group: .other, footprint: UInt64(6.4 * Double(1 << 30)), cpu: 0, processCount: 1, items: [])],
                                     sessions: [], readableTotal: 0, unreadableCount: 0)
        let c = SessionHeadroom(budget: RAMBudget(memory: memory, snapshot: result), sessions: [])
        XCTAssertEqual(c.overflow, 0)
        XCTAssertEqual(c.sessionCount, 0)
        XCTAssertEqual(c.state, .tight)
    }
}
