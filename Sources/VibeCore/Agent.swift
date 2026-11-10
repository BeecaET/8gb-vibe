import Foundation

/// One CLI AI agent session (Codex CLI, Gemini CLI...). Claude Code uses `ClaudeCodeSession`.
public struct AgentSession: Identifiable, Sendable, Hashable {
    public var id: String
    public var pid: Int32
    public var tool: String
    public var directory: String?
    /// Includes child processes (MCP servers, tools...).
    public var footprint: UInt64
    public var cpu: Double
    public var startDate: Date
    public var lastActive: Date
    /// For an agent bundled inside an app (Codex inside ChatGPT.app): that app's bundle path.
    /// Its RAM is taken out of the app's row so it is not counted twice.
    public var hostApp: String?

    public init(id: String, pid: Int32, tool: String, directory: String?, footprint: UInt64, cpu: Double,
                startDate: Date, lastActive: Date, hostApp: String? = nil) {
        self.id = id; self.pid = pid; self.tool = tool; self.directory = directory; self.footprint = footprint
        self.cpu = cpu; self.startDate = startDate; self.lastActive = lastActive; self.hostApp = hostApp
    }

    public init(_ p: ClaudeCodeSession) {
        self.init(id: p.id, pid: p.pid, tool: "Claude Code", directory: p.directory, footprint: p.footprint,
                  cpu: p.cpu, startDate: p.startDate, lastActive: p.lastActive)
    }

    public var projectName: String? { directory.map { ($0 as NSString).lastPathComponent } }
}

/// An open AI tool: a CLI agent (sessions grouped), an AI app, or an AI IDE.
public struct AITool: Identifiable, Sendable, Hashable {
    public enum Kind: Int, Sendable, CaseIterable, Comparable {
        case cli, apps, ide

        public var name: String {
            switch self {
            case .cli: return String(localized: "CLI agents", bundle: .main)
            case .apps: return String(localized: "AI apps", bundle: .main)
            case .ide: return String(localized: "AI IDEs", bundle: .main)
            }
        }

        public static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }
    }

    public var id: String { name }
    public var name: String
    public var kind: Kind
    /// .app bundle path used for the icon. nil for CLI agents.
    public var bundlePath: String?
    public var footprint: UInt64
    public var cpu: Double
    public var sessions: [AgentSession]
    public var startDate: Date
    public var lastActive: Date
    public var isFrontmost: Bool
    public var note: String?
}

public enum AIToolBuilder {
    /// AI apps with a UI, by display name.
    static let aiApps: Set<String> = ["Claude", "ChatGPT", "ChatGPT Classic", "Gemini", "Perplexity", "Copilot",
                                     "Microsoft Copilot", "Grok", "DeepSeek", "Le Chat", "Ollama", "LM Studio"]
    /// Display name of the Claude app's virtual machine row.
    public static var coworkVMName: String { String(localized: "Claude: Cowork VM", bundle: .main) }
    /// IDEs and coding apps with AI.
    static let ide: Set<String> = ["Cursor", "Antigravity", "Antigravity IDE", "Windsurf", "Visual Studio Code", "Code",
                                   "Zed", "Codex", "Kiro", "Trae", "Void"]

    /// Collects AI tools from the analysis result. Sorted by kind, then by RAM.
    public static func from(_ result: ProcessSnapshot) -> [AITool] {
        var items: [AITool] = []

        // CLI agents: group sessions by tool.
        let sessions = result.sessions.map(AgentSession.init) + result.agentSessions
        for (name, members) in Dictionary(grouping: sessions, by: \.tool) {
            let sorted = members.sorted { $0.startDate < $1.startDate }
            items.append(AITool(name: name, kind: .cli, bundlePath: nil,
                               footprint: sorted.reduce(0) { $0 + $1.footprint }, cpu: sorted.reduce(0) { $0 + $1.cpu },
                               sessions: sorted, startDate: sorted.first?.startDate ?? result.timestamp,
                               lastActive: sorted.map(\.lastActive).max() ?? result.timestamp, isFrontmost: false, note: nil))
        }

        // Apps and IDEs.
        let claudeVM = result.item(.claude, ItemName.claudeVM)
        for a in result.apps {
            let name = a.app.name
            let kind: AITool.Kind
            if aiApps.contains(name) { kind = .apps } else if ide.contains(name) { kind = .ide } else { continue }
            // Agents bundled in this app (Codex in ChatGPT.app) are listed as agent sessions: take their RAM out of the app row.
            let embedded = result.agentSessions.filter { $0.hostApp == a.app.bundlePath }
            let embeddedRAM = embedded.reduce(UInt64(0)) { $0 + $1.footprint }
            let embeddedCPU = embedded.reduce(0.0) { $0 + $1.cpu }
            let note = embedded.isEmpty ? nil
                : String(localized: "Excludes \(embedded.first?.tool ?? "") (\(Format.bytes(embeddedRAM))), shown under CLI agents.", bundle: .main)
            items.append(AITool(name: name, kind: kind, bundlePath: a.app.bundlePath,
                               footprint: a.footprint > embeddedRAM ? a.footprint - embeddedRAM : 0, cpu: max(0, a.cpu - embeddedCPU),
                               sessions: [], startDate: a.startDate, lastActive: a.lastActive,
                               isFrontmost: a.app.isFrontmost, note: note))
            // The Claude app's virtual machine (Cowork) gets its own row: about 1.8 GB even when only chatting.
            if name == "Claude", let vm = claudeVM, vm.footprint > 0 {
                items.append(AITool(name: coworkVMName, kind: .apps, bundlePath: a.app.bundlePath, footprint: vm.footprint,
                                   cpu: vm.cpu, sessions: [], startDate: vm.earliestStart, lastActive: vm.lastActive,
                                   isFrontmost: false,
                                   note: String(localized: "The Claude app's Cowork virtual machine, running for \(Format.duration(result.timestamp.timeIntervalSince(vm.earliestStart))). Quit the Claude app (Cmd+Q) when you are not using Cowork to give the RAM back.", bundle: .main)))
            }
        }
        return items.sorted { ($0.kind, UInt64.max - $0.footprint) < ($1.kind, UInt64.max - $1.footprint) }
    }
}

/// Rough estimate of how many more agent sessions fit in the RAM budget. Not a guarantee: macOS may swap earlier
/// (compression, file cache, spikes), so the UI always calls it an estimate.
public struct SessionHeadroom: Sendable, Hashable {
    /// What the estimate says.
    public enum State: Sendable, Hashable {
        /// Room for about this many more sessions.
        case room(Int)
        /// The budget is nearly full: not enough for one more session.
        case tight
        /// Apps already need more than the Mac's RAM: do not open more sessions.
        case short
    }

    public var state: State {
        if overflow > 0 { return .short }
        return sessionCount > 0 ? .room(sessionCount) : .tight
    }

    /// Number of extra sessions that fit. 0 when RAM is used up.
    public var sessionCount: Int
    /// RAM a new session needs (average of open sessions, or the default).
    public var perSession: UInt64
    /// RAM still free by the budget. 0 when over budget.
    public var availableRAM: UInt64
    /// How much the RAM apps need exceeds the Mac's RAM.
    public var overflow: UInt64

    /// Default RAM per session when there is no session to measure. Estimated from Claude Code sessions on an 8 GB Mac.
    public static let defaultValue: UInt64 = 250 << 20
    /// Reserved for the system and file cache, not counted as free.
    public static let reserve: UInt64 = 512 << 20

    /// Reserve used when none is passed: set from the Mac's optimization profile at launch.
    nonisolated(unsafe) public static var currentReserve: UInt64 = reserve

    public init(budget: RAMBudget, sessions: [AgentSession], reserve: UInt64 = SessionHeadroom.currentReserve) {
        let average = sessions.isEmpty ? Self.defaultValue : sessions.reduce(0) { $0 + $1.footprint } / UInt64(sessions.count)
        perSession = max(average, 100 << 20)
        let limit = budget.totalRAM > reserve ? budget.totalRAM - reserve : 0
        availableRAM = limit > budget.demand ? limit - budget.demand : 0
        overflow = budget.overflow
        sessionCount = Int(availableRAM / perSession)
    }
}

public enum AgentSessionBuilder {
    /// CLI agent sessions other than Claude Code: an agent process whose parent is not the same agent. Child processes are added up.
    /// Skips processes inside an .app bundle (for example the Codex app running `codex app-server` inside).
    public static func from(_ list: [ProcessRecord], cpu: [Int32: Double], directory: (Int32) -> String?,
                          lastActive: (String, Double) -> Date) -> [AgentSession] {
        let byPID = Dictionary(list.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        var children: [Int32: [Int32]] = [:]
        for t in list { children[t.ppid, default: []].append(t.pid) }

        var result: [AgentSession] = []
        for t in list {
            guard let name = DevProcessClassifier.agentName(t), name != "Claude Code", !t.path.contains(".app/") else { continue }
            if let parent = byPID[t.ppid], DevProcessClassifier.agentName(parent) == name { continue }
            var tree: [Int32] = []
            var queue = [t.pid]
            while let x = queue.popLast(), tree.count < 500 {
                tree.append(x)
                queue.append(contentsOf: children[x] ?? [])
            }
            let c = tree.reduce(0.0) { $0 + (cpu[$1] ?? 0) }
            let id = "agent:\(t.key)"
            result.append(AgentSession(id: id, pid: t.pid, tool: name, directory: directory(t.pid),
                                 footprint: tree.reduce(0) { $0 + (byPID[$1]?.footprint ?? 0) }, cpu: c,
                                 startDate: t.startDate, lastActive: lastActive(id, c)))
        }
        result += embeddedAgents(list, byPID: byPID, children: children, cpu: cpu, lastActive: lastActive)
        return result.sorted { $0.startDate < $1.startDate }
    }

    /// True for the Codex CLI bundled inside an app, for example
    /// /Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex (app-server, exec-server).
    public static func isEmbeddedCodex(_ path: String) -> Bool {
        path.contains(".app/Contents/Resources/codex-cli/")
    }

    /// The outer .app bundle path of a process path ("/Applications/ChatGPT.app/Contents/..." -> "/Applications/ChatGPT.app").
    static func outerBundle(_ path: String) -> String? {
        guard let r = path.range(of: ".app/") else { return nil }
        return String(path[..<r.lowerBound]) + ".app"
    }

    /// Codex bundled in an app: one session per host app process, made of every codex-cli process the app started
    /// and all their children. The app's UI (Codex Framework helpers) stays with the app row.
    static func embeddedAgents(_ list: [ProcessRecord], byPID: [Int32: ProcessRecord], children: [Int32: [Int32]],
                               cpu: [Int32: Double], lastActive: (String, Double) -> Date) -> [AgentSession] {
        var roots: [Int32: [ProcessRecord]] = [:]
        for t in list where isEmbeddedCodex(t.path) {
            // Roots only: a codex-cli process whose parent is not itself a codex-cli process.
            if let parent = byPID[t.ppid], isEmbeddedCodex(parent.path) { continue }
            roots[t.ppid, default: []].append(t)
        }
        return roots.compactMap { host, members -> AgentSession? in
            guard let first = members.min(by: { $0.startDate < $1.startDate }) else { return nil }
            var tree: [Int32] = []
            var queue = members.map(\.pid)
            while let x = queue.popLast(), tree.count < 500 {
                tree.append(x)
                queue.append(contentsOf: children[x] ?? [])
            }
            let c = tree.reduce(0.0) { $0 + (cpu[$1] ?? 0) }
            let id = "agent:embedded:\(byPID[host]?.key ?? first.key)"
            return AgentSession(id: id, pid: first.pid, tool: "Codex", directory: nil,
                                footprint: tree.reduce(0) { $0 + (byPID[$1]?.footprint ?? 0) }, cpu: c,
                                startDate: first.startDate, lastActive: lastActive(id, c), hostApp: outerBundle(first.path))
        }
    }
}
